package com.acevm.vmm.qemu

/**
 * 虚拟机后端统一抽象。当前仅实现 TCG（纯软件模拟）后端，
 * 后续可替换为 DroidVM（Gunyah 硬件虚拟化）等实现。
 */
interface VmmBackend {
    val isRunning: Boolean
    fun start()
    fun stop()
    /** 进程退出码，未启动或仍在运行时为 null */
    val exitCode: Int?
}

/**
 * QEMU 后端接口。面向未来 DroidVM / Gunyah 后端保留。
 */
interface VmmBackendProvider {
    fun provide(config: QemuConfig): VmmBackend
}
