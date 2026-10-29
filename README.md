# 固件手术刀 (Firmware Surgery)

root 环境下在手机本地拆包 → 手术(patch) → 重打包固件，产出 **AEmulator 可导入的 system.img**。

目标固件：ColorOS / 其它现代厂商固件（OPPO 系先打头）。
手术内容：关掉会拖死 system_server 的 OPPO 组件（`nwatchcall`/`AtlasService`/`OplusPerfCount` 等）、调 `build.prop`、精简冗余，让固件在 AEmulator 里活下来。

## 技术栈
- Flutter（UI）
- Kotlin 原生通道 `fw_surgery/engine`：root 执行（`su`）+ 捆绑 arm64 原生工具执行

## 流水线
```
选固件(OZIP/payload/system.img)
  → 拆包(payload-dumper-go / lpunpack)
  → 手术(改 build.prop / 删关 OPPO 组件 / 精简)
  → 重打包(erofs mkfs)
  → 输出 system.img → 导回 AEmulator
```

## 手术补丁
编辑 `lib/engine.dart` 里的 `PatchProfile`（可编辑的补丁配置），换固件不用重编 app。

## 构建
GitHub Actions：`.github/workflows/build-apk.yml` → `flutter build apk --release`。
