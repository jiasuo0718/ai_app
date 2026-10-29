package com.fwsurgery.app

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 固件手术刀 —— 原生侧：root 执行 + 捆绑 arm64 工具管理。
 * 通道 fw_surgery/engine:
 *   checkRoot              -> bool       是否已 root(su 可用且 uid=0)
 *   exec {command}         -> String     用 su 执行命令, 返回输出
 *   copyTool {asset,name}  -> String     把 assets/tools 下的二进制拷到缓存目录并赋 x 位, 返回绝对路径
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "fw_surgery/engine"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkRoot" -> result.success(checkRoot())
                "exec" -> {
                    val cmd = call.argument<String>("command") ?: ""
                    result.success(runShell(cmd))
                }
                "copyTool" -> {
                    val asset = call.argument<String>("asset") ?: ""
                    val name = call.argument<String>("name") ?: asset.substringAfterLast('/')
                    result.success(copyToolToCache(asset, name))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkRoot(): Boolean {
        val suPaths = listOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/vendor/bin/su", "/su/bin/su", "/system/bin/magisk"
        )
        val anySu = suPaths.any { File(it).exists() }
        if (!anySu) return false
        return runCatching {
            Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
                .inputStream.bufferedReader().readText().trim()
        }.getOrDefault("").let { it.contains("uid=0") || it.contains("gid=0") }
    }

    private fun runShell(cmd: String): String {
        return runCatching {
            val p = Runtime.getRuntime().exec(arrayOf("su", "-c", cmd))
            val out = p.inputStream.bufferedReader().readText()
            val err = p.errorStream.bufferedReader().readText()
            p.waitFor()
            (if (out.isNotBlank()) out else "") + (if (err.isNotBlank()) "\n$err" else "")
        }.getOrElse { "ERR: ${it.message}" }.trim()
    }

    /** 把 assets/tools 下的 arm64 二进制拷到可执行缓存目录并赋 x 位, 返回可执行路径(或 ERR: 前缀)。 */
    private fun copyToolToCache(asset: String, name: String): String {
        return runCatching {
            val dir = File(cacheDir, "tools").apply { mkdirs() }
            val f = File(dir, name)
            // Flutter 资产放在 APK 的 assets/flutter_assets/ 下, AssetManager 相对 assets/ 解析,
            // 因此必须加 flutter_assets/ 前缀, 否则 assets.open() 找不到(错误消息=asset路径)
            val realAsset = if (asset.startsWith("flutter_assets/")) asset else "flutter_assets/$asset"
            assets.open(realAsset).use { input -> f.outputStream().use { output -> input.copyTo(output) } }
            if (!f.exists() || f.length() == 0L) return@runCatching "ERR: 拷贝后文件为空 $name"
            Runtime.getRuntime().exec(arrayOf("su", "-c", "chmod 755 \"${f.absolutePath}\"")).waitFor()
            f.absolutePath
        }.getOrElse { "ERR: ${it.message}" }
    }
}
