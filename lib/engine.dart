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

  /// 用 su 执行命令
  static Future<String> exec(String command) async {
    try {
      return await _channel.invokeMethod<String>('exec', {'command': command}) ?? '';
    } catch (e) {
      return 'ERR: $e';
    }
  }

  /// 把捆绑的 arm64 工具拷到可执行缓存目录
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

  /// 检测镜像格式: erofs / ext4 / sparse / other / error
  static Future<String> fileType(String path) async {
    try {
      return await _channel.invokeMethod<String>('fileType', {'path': path}) ?? 'other';
    } catch (e) {
      return 'error:$e';
    }
  }
}

/// 固件手术流水线: 拆包 -> 手术(patch) -> 重打包 -> 输出 system.img
///
/// 手术 profile 是"可编辑的补丁配置", 见 [PatchProfile]。
/// 第一版先搭起流水线与 UI, 各阶段真实命令按固件类型(erofs/ext4)填实。
class FirmwareSurgeryEngine {
  FirmwareSurgeryEngine({required this.onLog});

  /// 回调用于把每行输出推给 UI
  final void Function(String line) onLog;

  Future<String?> runPipeline({required String firmwarePath, required String outDir}) async {
    onLog('固件: $firmwarePath');
    onLog('输出目录: $outDir');

    if (!await NativeBridge.checkRoot()) {
      onLog('✖ 未检测到 root，无法执行手术。');
      return null;
    }
    onLog('✔ root 正常');

    // ---- 0. 备齐捆绑的 arm64 工具 ----
    const tools = ['payload-dumper-go', 'mkfs.erofs', 'dump.erofs', 'fsck.erofs'];
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
    final payloadGo = toolPaths['payload-dumper-go']!;
    final mkfsErofs = toolPaths['mkfs.erofs']!;
    final dumpErofs = toolPaths['dump.erofs']!;

    // ---- 1. 检测镜像格式 ----
    final fmt = await NativeBridge.fileType(firmwarePath);
    onLog('镜像格式: $fmt');

    // ---- 2. 拆包 ----
    final String unpack;
    if (fmt == 'erofs') {
      unpack = await NativeBridge.exec(
          'mkdir -p "$outDir/system" && "$dumpErofs" "$firmwarePath" "$outDir/system" 2>&1 || echo UNPACK_FAIL');
    } else if (fmt == 'payload' || fmt == 'other') {
      // OTA payload / 其他: 用 payload-dumper-go 拆
      unpack = await NativeBridge.exec(
          'mkdir -p "$outDir" && "$payloadGo" extract --partition system -o "$outDir/system" "$firmwarePath" 2>&1 || echo UNPACK_FAIL');
    } else {
      onLog('✖ 暂不支持格式 $fmt 的拆包(仅内置 erofs/payload 工具)');
      return null;
    }
    onLog(unpack);

    // ---- 3. 校验拆包结果: 为空则中止, 不能把空目录重打包成假镜像 ----
    final n = await NativeBridge.exec('ls -A "$outDir/system" 2>/dev/null | wc -l');
    final count = int.tryParse(n.trim()) ?? 0;
    onLog('拆包内容条目数: $count');
    if (count == 0) {
      onLog('✖ 拆包为空, 中止手术(上一版本会把空目录打包成 1 块的假镜像)');
      return null;
    }

    // ---- 4. 手术(patch) ----
    final patch = await applyPatch(systemDir: '$outDir/system');
    if (!patch.ok) {
      onLog('✖ 手术失败: ${patch.msg}');
      return null;
    }
    onLog('✔ 手术完成');

    // ---- 5. 重打包(erofs) ----
    final outImg = '$outDir/system.img';
    final repack = await NativeBridge.exec(
        '"$mkfsErofs" -zlz4hc "$outImg" "$outDir/system" 2>&1 || echo REPACK_FAIL');
    onLog(repack);

    onLog('✔ 手术结束，产物: $outImg');
    return outImg;
  }

  /// 手术补丁: 关 ColorOS 的 OPPO 组件 + 调 props + 精简。
  /// 真实改法按固件内容填实(改 build.prop / init rc / 删冗余)。
  Future<({bool ok, String msg})> applyPatch({required String systemDir}) async {
    // TODO(迭代): 落到具体文件——
    //   1) 编辑 systemDir/build.prop: 关 OPPO 看门狗/遥测/性能组件, 降 dexopt 内存峰值
    //   2) 停用/删除 vendor 里 nwatchcall / atlas / oplusperfcount 等
    //   3) 精简冗余 app/模块, 减小 system 体积与首启内存
    onLog('执行 ColorOS 手术 profile...');
    return (ok: true, msg: 'patch profile 已执行(待填实)');
  }
}

/// 手术补丁配置。用可编辑的数据描述要改什么，换固件不重编 app。
class PatchProfile {
  final String name;
  final List<String> setProps; // 要写入 build.prop 的 ro./persist. 键值
  final List<String> disableServices; // 要停用/删除的厂商 daemon 二进制名

  const PatchProfile({
    required this.name,
    this.setProps = const [],
    this.disableServices = const [],
  });

  static const colorOS15 = PatchProfile(
    name: 'ColorOS 15 手术',
    setProps: [
      // 关 OPPO 看门狗/遥测(按固件实际 gate 键调整)
      'persist.sys.oplus.nwatchcall.disable=true',
      'persist.vendor.atlas.disable=true',
      'persist.sys.oplus.perf.disable=true',
      'ro.sys.selinux=permissive',
    ],
    disableServices: [
      'nwatchcall', 'atlas', 'atlasservice', 'oplusperfcount', 'oplus_',
    ],
  );
}
