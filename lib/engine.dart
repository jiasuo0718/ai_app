import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// 原生通道: 见 android/.../MainActivity.kt
class NativeBridge {
  static const _channel = MethodChannel('fw_surgery/engine');

  /// 是否已 root
  static Future<bool> checkRoot() async {
    try {
      return await _channel.invokeMethod<bool>('checkRoot') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 用 su 执行命令, 返回 stdout+stderr
  static Future<String> exec(String command) async {
    try {
      return await _channel.invokeMethod<String>('exec', {'command': command}) ?? '';
    } catch (e) {
      return 'ERR: $e';
    }
  }

  /// 把捆绑的 arm64 工具拷到可执行缓存目录(自动 chmod 755)
  static Future<String> copyTool(String asset, String name) async {
    try {
      return await _channel
          .invokeMethod<String>('copyTool', {'asset': asset, 'name': name}) ?? '';
    } catch (e) {
      return 'ERR: $e';
    }
  }

  /// 用 su 列出目录内容(每行 "D|路径"=目录 / "F|路径"=文件)
  static Future<List<String>> listDir(String path) async {
    try {
      final raw = await _channel.invokeMethod<String>('listDir', {'path': path}) ?? '';
      if (raw.startsWith('ERR')) return ['ERR|$raw'];
      final lines = raw.split('\n').where((l) => l.startsWith('D|') || l.startsWith('F|')).toList();
      return lines.isEmpty ? ['D|/'] : lines;
    } catch (e) {
      return ['ERR|$e'];
    }
  }
}

/// 固件手术流水线(v0.4 挂载版):
///   挂载(loop,rw) -> 删冗余 App + 改 build.prop -> 卸载
///   -> e2fsck 校验 -> resize2fs -M 收缩 -> 截断 -> 产物=输入镜像(就地瘦身)
class FirmwareSurgeryEngine {
  FirmwareSurgeryEngine({required this.onLog});

  /// 回调用于把每行输出推给 UI 黑框
  final void Function(String line) onLog;

  static const String _mnt = '/data/local/tmp/fw_mnt';

  Future<String?> runPipeline({required String firmwarePath, required String outDir}) async {
    onLog('固件: $firmwarePath');
    onLog('方案: Root 挂载原地精简 + resize2fs 收缩体积');

    if (!await NativeBridge.checkRoot()) {
      onLog('✖ 未检测到 root，无法执行手术。');
      return null;
    }
    onLog('✔ root 正常');

    // ---- 0. 工具: resize2fs(瘦身) + e2fsck(校验) + 依赖库(Termux 预编译) ----
    final tools = ['resize2fs', 'e2fsck', 'libblkid.so', 'libuuid.so', 'libandroid-posix-semaphore.so'];
    final toolPaths = <String, String>{};
    for (final t in tools) {
      final p = await NativeBridge.copyTool('assets/tools/$t', t);
      if (p.startsWith('ERR:')) {
        onLog('✖ 工具 $t 准备失败: $p');
        return null;
      }
      toolPaths[t] = p;
      onLog('✔ 工具就绪: $p');
    }
    final resize2fs = toolPaths['resize2fs']!;
    final e2fsck = toolPaths['e2fsck']!;
    final toolDir = File(resize2fs).parent.path;
    // e2fsck 依赖 Termux 的 libblkid/libuuid/semaphore, 运行时从这里找库
    const ld = 'export LD_LIBRARY_PATH="\$TOOL_DIR"; ';
    String withLib(String bin, String args) => '${ld.replaceAll('\$TOOL_DIR', toolDir)}"$bin" $args';
    final img = firmwarePath;

    // ---- 1. 挂载(带 setenforce 0 与 losetup 回退) ----
    if (!await _mount(img)) {
      onLog('✖ 挂载失败, 中止(已尝试 setenforce 0 / losetup)');
      return null;
    }

    // ---- 2. 精简 + 改 build.prop ----
    final slim = await _slimAndPatch();
    if (!slim) {
      await _umount();
      onLog('✖ 精简/修改失败, 已卸载');
      return null;
    }

    // ---- 3. 卸载 ----
    if (!await _umount()) {
      onLog('✖ 卸载失败, 请手动 umount $_mnt');
      return null;
    }

    // ---- 4. e2fsck 强制检查(防收缩损坏) ----
    onLog('运行 e2fsck -f -y(收缩前校验)...');
    final fsck = await NativeBridge.exec(withLib(e2fsck, '-f -y "$img" 2>&1; echo "RC=\$?"'));
    onLog(fsck);
    if (fsck.contains('RC=1') || fsck.contains('RC=2') || fsck.contains('RC=4')) {
      onLog('⚠ e2fsck 返回异常码, 仍继续尝试收缩(可在日志里复核)');
    }

    // ---- 5. resize2fs -M 收缩 + 解析块数 + 截断 ----
    final newSize = await _shrinkAndTruncate(img, resize2fs, toolDir);
    if (newSize == null) {
      onLog('✖ resize2fs 收缩/截断失败');
      return null;
    }

    onLog('✔ 手术完成, 产物(就地瘦身): $img (${newSize} 字节)');
    return img;
  }

  // ---------- 挂载 ----------
  Future<bool> _mount(String img) async {
    await NativeBridge.exec('mkdir -p $_mnt');

    // 尝试1: toybox 自带 loop 支持
    onLog('尝试 mount -o rw,loop ...');
    var r = await NativeBridge.exec('mount -o rw,loop "$img" $_mnt 2>&1 || echo MOUNT_FAIL');
    if (r.contains('MOUNT_FAIL')) {
      onLog('失败, setenforce 0 后重试...');
      await NativeBridge.exec('setenforce 0 2>&1 || true');
      final se = await NativeBridge.exec('getenforce 2>&1');
      onLog('SELinux 状态: ${se.trim()}');
      r = await NativeBridge.exec('mount -o rw,loop "$img" $_mnt 2>&1 || echo MOUNT_FAIL');
    }
    if (!r.contains('MOUNT_FAIL')) {
      onLog('✔ 挂载成功');
      return _mounted();
    }

    // 尝试2: losetup 显式绑定(自动补 loop 节点, 兼容 /dev/block/loopN 与 /dev/loopN)
    onLog('回退 losetup + mount(自动补 loop 节点)...');
    final loopInfo = await NativeBridge.exec('ls /sys/block/ 2>/dev/null | grep -i loop || echo NO_LOOP_DEVS');
    onLog('内核 loop 设备: ${loopInfo.trim()}');
    final losetup = await NativeBridge.exec(
      'ok=""; '
      'for n in 0 1 2 3 4 5 6 7; do '
      '[ -e /dev/block/loop\$n ] || mknod /dev/block/loop\$n b 7 \$n 2>/dev/null; '
      '[ -e /dev/loop\$n ] || mknod /dev/loop\$n b 7 \$n 2>/dev/null; '
      'if losetup /dev/block/loop\$n "$img" 2>/dev/null; then '
      'if mount -t ext4 -o rw /dev/block/loop\$n \$_mnt 2>/dev/null; then '
      'echo "LOOPOK:/dev/block/loop\$n"; ok=1; break; '
      'else losetup -d /dev/block/loop\$n 2>/dev/null; fi; fi; '
      'if [ -e /dev/loop\$n ] && losetup /dev/loop\$n "$img" 2>/dev/null; then '
      'if mount -t ext4 -o rw /dev/loop\$n \$_mnt 2>/dev/null; then '
      'echo "LOOPOK:/dev/loop\$n"; ok=1; break; '
      'else losetup -d /dev/loop\$n 2>/dev/null; fi; fi; '
      'done; '
      '[ -z "\$ok" ] && { echo "LOSETUP_ERR:"; losetup /dev/block/loop0 "$img" 2>&1 | head -3; '
      'mount -t ext4 -o rw /dev/block/loop0 \$_mnt 2>&1 | head -3; }; '
      'echo LOOPDONE');
    onLog(losetup);
    if (losetup.contains('LOOPOK')) {
      final lp = RegExp(r'LOOPOK:(\S+)').firstMatch(losetup)?.group(1) ?? 'loop';
      onLog('✔ losetup 挂载成功($lp)');
      return _mounted();
    }
    onLog('✖ 挂载全部失败(原因见上方 LOSETUP_ERR)');
    return false;
  }

  Future<bool> _mounted() async {
    final probe = await NativeBridge.exec('ls -A \$_mnt 2>/dev/null | wc -l');
    onLog('挂载点条目数: ${probe.trim()}');
    return true;
  }

  Future<bool> _umount() async {
    onLog('sync + umount ...');
    final r = await NativeBridge.exec('sync; umount \$_mnt 2>&1 || echo UMNT_FAIL');
    final ok = !r.contains('UMNT_FAIL');
    onLog(ok ? '✔ 已卸载' : '✖ 卸载失败: $r');
    return ok;
  }

  // ---------- 精简 + 改 build.prop ----------
  Future<bool> _slimAndPatch() async {
    bool anyOk = false;

    // 2a. 删除冗余预装 App(仅 system/app 下, 不动 priv-app 核心服务)
    for (final name in PatchProfile.colorOS15.removeApps) {
      final target = '$_mnt/system/app/$name';
      final exists = await NativeBridge.exec('ls -d "$target" 2>/dev/null | wc -l');
      if ((int.tryParse(exists.trim()) ?? 0) > 0) {
        final r = await NativeBridge.exec('rm -rf "$target" && echo RM_OK');
        onLog('✂ 删除 $name: ${r.contains('RM_OK') ? '已删' : '失败'}');
        anyOk = true;
      } else {
        onLog('- 跳过 $name(不存在)');
      }
    }

    // 2b. 追加 build.prop(分区根或 system/ 下二选一)
    final bp = await NativeBridge.exec(
      'BP=""; [ -f \$_mnt/build.prop ] && BP=\$_mnt/build.prop; '
      '[ -f \$_mnt/system/build.prop ] && BP=\$_mnt/system/build.prop; echo "\$BP"');
    final bpPath = bp.trim();
    if (bpPath.isEmpty) {
      onLog('⚠ 未找到 build.prop');
    } else {
      onLog('build.prop 位于: $bpPath');
      for (final prop in PatchProfile.colorOS15.setProps) {
        await NativeBridge.exec('echo "$prop" >> "$bpPath" && echo PROP_OK');
        onLog('✎ build.prop += $prop');
      }
      anyOk = true;
    }
    return anyOk;
  }

  // ---------- resize2fs -M 收缩 + 截断 ----------
  Future<int?> _shrinkAndTruncate(String img, String resize2fs, String toolDir) async {
    onLog('运行 resize2fs -M(收缩到最小块数)...');
    final cmd = 'export LD_LIBRARY_PATH="$toolDir"; "$resize2fs" -M "$img"';
    // 用 Dart Process.run 捕获 su 子进程的 stdout(便于正则解析块数)
    String out;
    try {
      final p = await Process.run('su', ['-c', cmd], stdoutEncoding: utf8);
      out = (p.stdout as String?) ?? '';
      if (p.exitCode != 0 && out.trim().isEmpty) {
        out = (p.stderr as String?) ?? out; // 输出可能走 stderr
      }
    } catch (e) {
      // Process.run 在部分环境不可用时回退原生通道(同样能拿到输出)
      onLog('(Process.run 不可用, 回退原生 su 通道: $e)');
      out = await NativeBridge.exec(cmd);
    }
    onLog(out);

    // 解析 "Resizing the filesystem to N (4k) blocks" / "is now N (4k) blocks long"
    final m = RegExp(r'to\s+(\d+)\s+\((\d+)k\)\s+blocks').firstMatch(out);
    if (m == null) {
      onLog('✖ 未能从 resize2fs 输出解析出块数(输出见上)');
      return null;
    }
    final blocks = int.parse(m.group(1)!);
    final k = int.parse(m.group(2)!);
    final newSize = blocks * k * 1024;
    onLog('解析到块数 $blocks (${k}k), 新体积 = $newSize 字节');

    // 截断: 优先 Dart File(经 RandomAccessFile.truncate), 权限不足回退 su truncate
    var truncated = false;
    try {
      final f = File(img);
      if (await f.exists()) {
        final raf = await f.open(mode: FileMode.write);
        await raf.truncate(newSize);
        await raf.close();
        truncated = true;
        onLog('✔ Dart File(RandomAccessFile).truncate 成功');
      }
    } catch (_) {}
    if (!truncated) {
      final r = await NativeBridge.exec('truncate -s $newSize "$img" && echo TRUNK_OK');
      truncated = r.contains('TRUNK_OK');
      onLog(truncated ? '✔ su truncate 成功' : '✖ 截断失败: $r');
    }
    if (!truncated) return null;

    final sz = await NativeBridge.exec('stat -c %s "$img" 2>/dev/null');
    onLog('产物实际大小: ${sz.trim()} 字节');
    return newSize;
  }
}

/// 手术补丁配置。用可编辑的数据描述要改什么，换固件不重编 app。
class PatchProfile {
  final String name;
  final List<String> setProps; // 要追加进 build.prop 的 ro./persist. 键值
  final List<String> removeApps; // system/app 下要删除的预装 App 目录名

  const PatchProfile({
    required this.name,
    this.setProps = const [],
    this.removeApps = const [],
  });

  static const colorOS15 = PatchProfile(
    name: 'ColorOS 手术',
    setProps: [
      'ro.config.low_ram=true',
      'ro.sys.fw.bg_apps_limit=12',
      'persist.sys.oplus.nwatchcall.disable=true',
      'persist.vendor.atlas.disable=true',
    ],
    removeApps: [
      'OPPOStore', 'HeyTapStore', 'HeyTapCloudService', 'HeyTapTheme',
      'OPPOThemeStore', 'OPPOCloud', 'OPPOSettingsIntelligence',
    ],
  );
}
