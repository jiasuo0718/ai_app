package com.acevm.vmm.qemu

import android.util.Log
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * 基于 QEMU-TCG 的后端实现。
 *
 * 关键点（参考 DroidQEMU 的规避思路）：
 * - Android 的 /data 分区默认 noexec，直接 exec 动态链接 ELF 会失败。
 *   两种解法：
 *     1) QEMU 使用静态编译（纯静态 ELF，无 interpreter），可直接 exec —— 推荐用于 TCG 版本。
 *     2) 动态链接版本需借用 termux 的 linker：`/data/data/com.termux/files/usr/bin/linker64`
 *        作为 interpreter 手动加载，或用 patchelf 改写 ELF 的 PT_INTERP。
 *   本实现默认假设 QEMU 为静态/半静态编译，若 exec 失败会把错误抛给调用方。
 *
 * 显示与输入：
 * - `-vnc unix:<socket>` 让 QEMU 在本机创建 unix domain socket 供 VNC client 连接。
 * - `-usbdevice tablet` 提供绝对坐标的 USB 触控板设备，VNC 端发送 pointer event 即可映射触摸。
 */
class QemuTcgBackend(
    private val qemuBinary: File,
    private val config: QemuConfig,
) : VmmBackend {

    private val processRef = AtomicReference<Process?>()
    private val exitCodeRef = AtomicReference<Int?>(null)
    private var streamJob: Job? = null

    override val isRunning: Boolean
        get() = processRef.get()?.isAlive == true

    override val exitCode: Int?
        get() = exitCodeRef.get()

    override fun start() {
        // 幂等：若已在运行则先停掉
        if (isRunning) stop()

        require(qemuBinary.exists() && qemuBinary.canExecute()) {
            "QEMU 二进制不存在或无执行权限: ${qemuBinary.absolutePath}"
        }
        require(config.rootfsImg.exists()) {
            "rootfs 镜像不存在: ${config.rootfsImg.absolutePath}"
        }

        // 预清理旧的 VNC socket（QEMU 不会覆盖已存在的 unix socket）
        config.vncSocket.delete()

        val cmd = buildCommand()
        Log.i(TAG, "启动 QEMU: ${cmd.joinToString(" ")}")

        try {
            val builder = ProcessBuilder(cmd)
            builder.directory(config.rootfsImg.parentFile)
            builder.redirectErrorStream(true) // 合并 stdout/stderr，便于统一日志
            val process = builder.start()
            processRef.set(process)
            exitCodeRef.set(null)
            forwardOutput(process)
        } catch (e: Exception) {
            Log.e(TAG, "启动 QEMU 失败", e)
            throw e
        }
    }

    override fun stop() {
        val p = processRef.get() ?: return
        try {
            p.destroy()
            // TCG 进程通常响应 SIGTERM；若 2s 未退出则强杀
            if (p.isAlive) {
                p.waitFor(2, java.util.concurrent.TimeUnit.SECONDS)
            }
            if (p.isAlive) p.destroyForcibly()
        } catch (e: Exception) {
            Log.w(TAG, "停止 QEMU 异常", e)
        } finally {
            streamJob?.cancel()
            processRef.set(null)
        }
    }

    /**
     * 构造 QEMU 启动命令行。
     * 对应计划书给定参数，并补齐 aarch64 virt 机器类型。
     */
    private fun buildCommand(): List<String> {
        val args = mutableListOf<String>()
        args += qemuBinary.absolutePath
        // aarch64 通用 virt 板型（默认板型，显式声明便于扩展）
        args += "-machine"; args += "virt"
        args += "-cpu"; args += "cortex-a76"          // 骁龙 8 Gen3 主核同架构，TCG 下可选
        args += "-accel"; args += "tcg,thread=multi,tb-size=1024"
        args += "-smp"; args += config.cpuCores.toString()
        args += "-m"; args += config.memoryMb.toString()

        // 磁盘：virtio-blk 挂载 rootfs
        args += "-device"; args += "virtio-blk-device,drive=rootfs"
        args += "-drive"; args += "file=${config.rootfsImg.absolutePath},format=raw,if=none,id=rootfs"

        // 显示：本地 unix socket VNC
        args += "-vnc"; args += "unix:${config.vncSocket.absolutePath}"

        // 输入：USB tablet 绝对坐标
        if (config.usbTablet) {
            args += "-usbdevice"; args += "tablet"
        }

        // 串口日志：便于调试客户机内核（阶段四验证 kprobe / SukiSU 用）
        args += "-serial"; args += "mon:stdio"

        // 用户自定义透传参数
        args += config.extraArgs

        return args
    }

    /** 把 QEMU 的输出流转发给一个回调（用于日志控制台展示） */
    private fun forwardOutput(process: Process, scope: CoroutineScope = CoroutineScope(Dispatchers.IO)) {
        streamJob = scope.launch {
            process.inputStream.bufferedReader().forEachLine { line ->
                onLogLine(line)
            }
            // 进程结束，记录退出码
            exitCodeRef.set(process.waitFor())
            onExit()
        }
    }

    /** 日志回调，可在上层 UI 中展示 */
    var onLogLine: (String) -> Unit = {}
    var onExit: () -> Unit = {}

    private companion object {
        const val TAG = "AceVM/Qemu"
    }
}
