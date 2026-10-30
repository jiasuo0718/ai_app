package com.acevm.vmm.vm

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.acevm.vmm.qemu.AssetExtractor
import com.acevm.vmm.qemu.QemuConfig
import com.acevm.vmm.qemu.QemuTcgBackend
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File

/**
 * 虚拟机控制器：管理 QEMU 进程生命周期、日志、参数配置。
 * 阶段二交付：一键启动 / 停止 + 日志控制台 + 参数配置。
 */
class VmViewModel(private val appContext: Context) : ViewModel() {

    private val baseDir = File(appContext.filesDir, "vm")
    private var backend: QemuTcgBackend? = null

    // ---- 状态 ----
    private val _running = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running.asStateFlow()

    private val _logs = MutableStateFlow<List<String>>(emptyList())
    val logs: StateFlow<List<String>> = _logs.asStateFlow()

    private val _status = MutableStateFlow<String>("待启动")
    val status: StateFlow<String> = _status.asStateFlow()

    // ---- 配置 ----
    private val _cpuCores = MutableStateFlow(4)
    val cpuCores: StateFlow<Int> = _cpuCores.asStateFlow()

    private val _memoryMb = MutableStateFlow(4096)
    val memoryMb: StateFlow<Int> = _memoryMb.asStateFlow()

    /** 供 UI 手动指定 rootfs 镜像路径 */
    private var rootfsOverride: File? = null

    init {
        baseDir.mkdirs()
    }

    fun setCpuCores(n: Int) { _cpuCores.value = n.coerceIn(1, 8) }
    fun setMemoryMb(m: Int) { _memoryMb.value = m.coerceIn(1024, 8192) }
    fun setRootfs(file: File) { rootfsOverride = file }

    fun start() {
        if (_running.value) return
        _logs.value = emptyList()
        appendLog("== 准备启动 QEMU ==")
        viewModelScope.launch(Dispatchers.IO) {
            try {
                // 1) 从 assets 解压 QEMU 二进制（阶段二：内置到 assets/qemu/）
                val qemuDir = File(baseDir, "qemu")
                qemuDir.mkdirs()
                val qemuBin = AssetExtractor.extract(
                    appContext, "qemu/qemu-system-aarch64", qemuDir, executable = true
                )
                AssetExtractor.extractDir(appContext, "qemu/lib", File(qemuDir, "lib"))

                // 2) 构造配置
                val rootfs = rootfsOverride ?: File(baseDir, "rootfs.img")
                val config = QemuConfig(
                    cpuCores = _cpuCores.value,
                    memoryMb = _memoryMb.value,
                    rootfsImg = rootfs,
                    vncSocket = File(baseDir, "vnc.sock"),
                )

                // 3) 创建后端并启动
                val vm = QemuTcgBackend(qemuBin, config).apply {
                    onLogLine = { line -> appendLog(line) }
                    onExit = { viewModelScope.launch { _running.value = false } }
                }
                backend = vm
                vm.start()
                _status.value = "运行中 (${config.cpuCores}核 / ${config.memoryMb}MB)"
                _running.value = true
            } catch (e: Exception) {
                _status.value = "启动失败"
                appendLog("错误: ${e.message}")
            }
        }
    }

    fun stop() {
        if (!_running.value) return
        viewModelScope.launch(Dispatchers.IO) {
            backend?.stop()
            backend = null
            _running.value = false
            _status.value = "已停止"
            appendLog("== QEMU 已停止 ==")
        }
    }

    private fun appendLog(line: String) {
        _logs.value = (_logs.value + line).takeLast(200)
    }

    override fun onCleared() {
        backend?.stop()
        super.onCleared()
    }

    companion object {
        /** 供 viewModels { } 使用，注入 ApplicationContext */
        val Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                // 依赖注入简化：这里通过静态 Application 持有者取 context
                return VmViewModel(AppContextHolder.get()) as T
            }
        }
    }
}

/** 简单的 Application 持有者，供无构造参数 ViewModel 取 Context（生产可换 Dagger/Hilt） */
object AppContextHolder {
    @Volatile
    private var appContext: Context? = null
    fun init(ctx: Context) { appContext = ctx.applicationContext }
    fun get(): Context = appContext ?: throw IllegalStateException("AppContextHolder 未初始化")
}
