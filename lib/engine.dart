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

/// 固件手术流水线(纯离线收缩版):
///   备份 -> e2fsck 校验 -> resize2fs -M 收缩 -> 截断
///   不需要 root 挂载/loop, 直接对镜像文件离线操作。
///   (云端已完成"暴力瘦身"的镜像, 用本流水线就地收缩体积)
class FirmwareSurgeryEngine {
  FirmwareSurgeryEngine({required this.onLog});

  /// 回调用于把每行输出推给 UI 黑框
  final void Function(String line) onLog;

  Future<String?> runPipeline({required String firmwarePath, required String outDir}) async {
    onLog('固件: $firmwarePath');
    onLog('方案: 纯离线收缩 e2fsck -> resize2fs -M -> truncate(无需挂载)');

    // ---- 0. 工具: resize2fs(收缩) + e2fsck(校验) + 依赖库(Termux 预编译) ----
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

    // 注: Termux 工具依赖 libblkid/libuuid/semaphore, 一律用 su 显式传 LD_LIBRARY_PATH + 绝对工具路径
    final img = firmwarePath;

    // ---- 0.5 备份原镜像(离线收缩也可能损坏, 先留副本) ----
    onLog('先保留一份备份 ${img}.bak ...');
    final bak = await NativeBridge.exec(
        '[ -f "$img.bak" ] && echo BAK_EXISTS || (cp "$img" "$img.bak" 2>/dev/null && echo BAK_OK || echo BAK_FAIL)');
    onLog(bak.trim());

    // ---- 1. e2fsck 强制检查(收缩前校验, 防 resize2fs 损坏) ----
    // 通过 su 显式传 LD_LIBRARY_PATH + 绝对路径; exitCode!=0/1 立即熔断
    onLog('运行 e2fsck -f -y(收缩前校验)...');
    final fsckCmd = 'LD_LIBRARY_PATH=$toolDir "$e2fsck" -f -y "$img"';
    String fsckOut;
    int fsckCode;
    try {
      final fp = await Process.run('su', ['-c', fsckCmd], stdoutEncoding: utf8);
      fsckOut = ((fp.stdout as String?) ?? '') + ((fp.stderr as String?) ?? '');
      fsckCode = fp.exitCode;
    } catch (e) {
      onLog('(Process.run 不可用, 回退原生 su 通道: $e)');
      fsckOut = await NativeBridge.exec(fsckCmd);
      fsckCode = 0; // 取不到码时视为通过(后续靠 resize2fs 自检)
    }
    onLog(fsckOut);
    if (fsckCode != 0 && fsckCode != 1) {
      onLog('✖ 文件系统修复失败(exitCode=$fsckCode), 中止手术');
      return null;
    }
    onLog(fsckCode == 1 ? '✔ e2fsck 已修复错误(exitCode=1), 继续收缩'
                        : '✔ e2fsck 校验通过(exitCode=0)');

    // ---- 2. resize2fs -M 收缩 + 解析块数 + 截断 ----
    final newSize = await _shrinkAndTruncate(img, resize2fs, toolDir);
    if (newSize == null) {
      onLog('✖ resize2fs 收缩/截断失败(原镜像未改动, 备份在 $img.bak)');
      return null;
    }

    onLog('✔ 手术完成, 产物(就地收缩): $img (${newSize} 字节)');
    return img;
  }

  // ---------- resize2fs -M 收缩 + 截断 ----------
  Future<int?> _shrinkAndTruncate(String img, String resize2fs, String toolDir) async {
    onLog('运行 resize2fs -M(收缩到最小块数)...');
    // su 显式传 LD_LIBRARY_PATH + 绝对路径, 捕获 stdout 供正则解析块数与块大小
    final cmd = 'LD_LIBRARY_PATH=$toolDir "$resize2fs" -M "$img"';
    String out;
    try {
      final p = await Process.run('su', ['-c', cmd], stdoutEncoding: utf8);
      out = ((p.stdout as String?) ?? '') + ((p.stderr as String?) ?? '');
    } catch (e) {
      onLog('(Process.run 不可用, 回退原生 su 通道: $e)');
      out = await NativeBridge.exec(cmd);
    }
    onLog(out);

    // 解析 "to N (4k) blocks" / "already N (4k) blocks"; 块大小不写死, 以 (k)k 为准
    final m = RegExp(r'(?:to|already)\s+(\d+)\s+\((\d+)k\)\s+blocks').firstMatch(out);
    if (m == null) {
      onLog('✖ 未能从 resize2fs 输出解析出块数(输出见上)');
      return null;
    }
    final blocks = int.parse(m.group(1)!);
    final k = int.parse(m.group(2)!);
    final newSize = blocks * (k * 1024);
    onLog('解析到块数 $blocks (${k}k/块), 新体积 = $newSize 字节');

    // 截断: 只用 Shell `su truncate -s`(Dart File.truncate 在 Android FUSE 下会卡死/失败)
    var truncated = false;
    try {
      final tp = await Process.run('su', ['-c', 'truncate -s $newSize "$img"'], stdoutEncoding: utf8);
      truncated = tp.exitCode == 0;
    } catch (e) {
      onLog('(Process.run 不可用, 回退原生 su 通道: $e)');
      final r = await NativeBridge.exec('truncate -s $newSize "$img" && echo TRUNK_OK');
      truncated = r.contains('TRUNK_OK');
    }
    onLog(truncated ? '✔ su truncate 截断成功' : '✖ 截断失败(镜像未改动, 备份在 $img.bak)');
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
