# AceVM — 基于 QEMU-TCG 的独立安卓虚拟机 APP

> 代号 AceVM。宿主：一加 Ace6（骁龙 8 Gen 3，16G RAM，已解锁 BL 并 Root）。
> 宿主内核不开放 `/dev/kvm`、`/dev/gunyah`，且**不允许刷写/修改宿主内核（零风险原则）**，因此使用 QEMU 纯软件模拟（TCG）。

## 项目目标

开发一款独立 Android APK，内置 QEMU-TCG 引擎，提供完整图形界面，一键启动/管理完全自定义的客户机（Guest OS）。核心诉求：客户机内运行自编译内核（开启 `CONFIG_MODULES`、`CONFIG_KPROBES`），并成功加载 SukiSU（LKM 模式）。界面风格对标光速虚拟机。

> TCG 纯软件模拟，不追求大型游戏性能，重点是**整条链路完全打通**。

## 当前进度

- [x] **阶段一**：项目初始化 + GitHub Actions 自动构建 Debug APK（`.github/workflows/build-apk.yml`）
- [x] **阶段二**：QEMU 引擎集成与启动（二进制解压、进程拉起、一键启停、日志控制台）
- [ ] 阶段三：VNC 画面渲染 + 触控转发
- [ ] 阶段四：客户机内核（开启 MODULES/KPROBES）+ SukiSU 集成

## 技术栈

- Kotlin + Jetpack Compose（Material3）
- AGP 8.5.2 / Kotlin 2.0.20 / Gradle 8.14.2 / JDK 17
- 后端抽象：`VmmBackend` 接口，当前实现 `QemuTcgBackend`
- 显示：`-vnc unix:<socket>` 本地 unix domain socket，App 内自绘 VNC client
- 输入：`-usbdevice tablet` 绝对坐标触控板

## 目录结构

```
app/src/main/java/com/acevm/vmm/
├── MainActivity.kt          # 入口
├── qemu/
│   ├── VmmBackend.kt        # 后端抽象接口
│   ├── QemuTcgBackend.kt    # QEMU-TCG 实现（进程管理 + 命令行构造）
│   ├── QemuConfig.kt        # 运行配置（CPU/内存/镜像/VNC socket）
│   └── AssetExtractor.kt    # 从 assets/zip 解压 QEMU 二进制并赋执行权限
├── vm/
│   └── VmViewModel.kt       # 生命周期管理、日志流、参数状态
└── ui/
    └── MainScreen.kt        # 参数配置 + 启动/停止 + 日志控制台
```

## QEMU 启动参数（阶段二核心）

```text
qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a76 \
  -accel tcg,thread=multi,tb-size=1024 \
  -smp 4 \
  -m 4096 \
  -device virtio-blk-device,drive=rootfs \
  -drive file=rootfs.img,format=raw,if=none,id=rootfs \
  -vnc unix:/data/user/0/com.acevm.vmm/files/vm/vnc.sock \
  -usbdevice tablet \
  -serial mon:stdio
```

## 关键实现说明

### Android 上 exec QEMU 的坑（参考 DroidQEMU）
Android 的 `/data` 分区默认 **noexec**，直接 exec 动态链接 ELF 会失败。两种解法：
1. **静态编译 QEMU**（纯静态 ELF，无 interpreter）—— 推荐用于 TCG 版本；
2. 动态链接版本需借用 termux linker（`.../usr/bin/linker64`）作为 interpreter 手动加载，或 `patchelf` 改写 `PT_INTERP`。

本工程 `QemuTcgBackend` 默认假设 QEMU 为静态/半静态编译，exec 失败会抛出异常并显示在日志控制台。

### 二进制来源
- 静态编译的 `qemu-system-aarch64` 放入 `app/src/main/assets/qemu/`
- 依赖动态库（如有）放入 `app/src/main/assets/qemu/lib/`
- `AssetExtractor` 首次启动自动解压到 App 私有目录并赋执行权限

## 构建

本地（需 JDK 17）：
```bash
./gradlew assembleDebug
# 产物: app/build/outputs/apk/debug/app-debug.apk
```

GitHub Actions：push 到 `main` 自动构建并上传 `acevm-debug-apk` Artifact。

## 参考开源项目

- **DroidQEMU** — QEMU 二进制提取 / linker 绕过 noexec
- **Vectras-VM-Android** — aarch64 启动参数、VNC 渲染、触控转发
- **DroidVM** — UI 布局、参数配置面板
- **SukiSU-Ultra** — GKI 内核 LKM 编译与 init_boot 修补流程

## 许可证

参考项目均为 GPL-3.0 / 相关开源许可。本仓库代码在 [LICENSE](LICENSE)（待定）下发布。

---

*历史说明：本仓库曾用于「固件手术刀」Flutter 工具开发，工作区已清空并重置为 AceVM 工程；原代码已备份，git 历史保留可追溯。*
