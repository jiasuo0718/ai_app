package com.acevm.vmm.qemu

import android.content.Context
import java.io.File
import java.util.zip.ZipFile

/**
 * 首次启动时从 App assets / 下载包中提取 QEMU 二进制与配套动态库到私有目录，
 * 并设置可执行权限。参考 DroidQEMU：二进制放 App 私有目录，配合 Android linker 绕过
 * /data 的 noexec 限制执行。
 */
object AssetExtractor {

    private const val TAG = "AceVM/Extractor"

    /**
     * 从 assets 解压单个文件。
     * @param assetPath assets 内相对路径
     * @param targetDir 目标目录
     * @param executable 是否标记为可执行（QEMU 二进制需要）
     */
    fun extract(context: Context, assetPath: String, targetDir: File, executable: Boolean = false): File {
        targetDir.mkdirs()
        val target = File(targetDir, File(assetPath).name)
        context.assets.open(assetPath).use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        if (executable) {
            // 保留执行权限（宿主已 root，亦可提升到 755）
            target.setExecutable(true, false)
            target.setReadable(true, false)
        }
        return target
    }

    /**
     * 从 assets 目录批量解压（例如解压 lib 目录下的所有 .so 动态库）。
     */
    fun extractDir(context: Context, assetDir: String, targetDir: File): List<File> {
        targetDir.mkdirs()
        val entries = context.assets.list(assetDir) ?: return emptyList()
        return entries.map { name ->
            extract(context, "$assetDir/$name", targetDir, executable = name.endsWith(".so") || name.endsWith(".elf"))
        }
    }

    /**
     * 从外部下载/导入的 zip 包中提取 QEMU 二进制。
     * @param zipPath 本地 zip 路径
     * @param entryName zip 内二进制条目名，如 "bin/qemu-system-aarch64"
     * @param targetDir 目标目录
     */
    fun extractFromZip(zipPath: File, entryName: String, targetDir: File, executable: Boolean = true): File {
        targetDir.mkdirs()
        val target = File(targetDir, File(entryName).name)
        ZipFile(zipPath).use { zip ->
            val entry = zip.getEntry(entryName) ?: error("zip 中未找到条目: $entryName")
            zip.getInputStream(entry).use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
        }
        if (executable) {
            target.setExecutable(true, false)
            target.setReadable(true, false)
        }
        return target
    }

    /**
     * 设置执行权限并返回可执行文件。
     * 宿主已 root 时可尝试用 chmod 直接提权，兼容非 root 场景使用 setExecutable。
     */
    fun makeExecutable(file: File): File {
        file.setExecutable(true, false)
        file.setReadable(true, false)
        return file
    }
}
