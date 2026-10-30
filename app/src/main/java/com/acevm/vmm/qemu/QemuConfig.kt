package com.acevm.vmm.qemu

import java.io.File

/**
 * 虚拟机运行配置。
 * 对应计划书阶段二：CPU 核心数、内存大小、rootfs 镜像、VNC unix socket。
 */
data class QemuConfig(
    val cpuCores: Int = 4,
    val memoryMb: Int = 4096,
    val rootfsImg: File,
    val vncSocket: File,
    /** 是否启用 tablet 绝对坐标输入（配合触控转发） */
    val usbTablet: Boolean = true,
    /** 额外透传的 QEMU 参数（键值对形式，便于扩展） */
    val extraArgs: List<String> = emptyList(),
) {
    companion object {
        /** 从 App 私有目录构造一份默认配置 */
        fun create(baseDir: File, rootfsName: String = "rootfs.img"): QemuConfig {
            return QemuConfig(
                rootfsImg = File(baseDir, rootfsName),
                vncSocket = File(baseDir, "vnc.sock"),
            )
        }
    }
}
