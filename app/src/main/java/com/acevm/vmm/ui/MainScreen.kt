package com.acevm.vmm.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.acevm.vmm.vm.VmViewModel

/**
 * 阶段二主界面：虚拟机参数配置 + 启动/停止 + 日志控制台。
 * 阶段三将在此基础上叠加 VNC 画面显示区与触控转发。
 */
@Composable
fun MainScreen(viewModel: VmViewModel) {
    val running by viewModel.running.collectAsState()
    val status by viewModel.status.collectAsState()
    val logs by viewModel.logs.collectAsState()
    val cpuCores by viewModel.cpuCores.collectAsState()
    val memoryMb by viewModel.memoryMb.collectAsState()

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("AceVM — QEMU-TCG 虚拟机", style = MaterialTheme.typography.headlineSmall)

            // ---- 参数配置卡片 ----
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = cpuCores.toString(),
                        onValueChange = { it.toIntOrNull()?.let(viewModel::setCpuCores) },
                        label = { Text("CPU 核心数") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = memoryMb.toString(),
                        onValueChange = { it.toIntOrNull()?.let(viewModel::setMemoryMb) },
                        label = { Text("内存 (MB)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }

            // ---- 启动/停止按钮 ----
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Button(
                    onClick = { if (running) viewModel.stop() else viewModel.start() },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(if (running) "停止" else "启动")
                }
                Spacer(Modifier.width(12.dp))
                Text(status, style = MaterialTheme.typography.bodyMedium)
            }

            // ---- 日志控制台 ----
            Text("日志控制台", style = MaterialTheme.typography.titleMedium)
            Card(modifier = Modifier.weight(1f).fillMaxWidth()) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(8.dp),
                    reverseLayout = false
                ) {
                    items(logs) { line ->
                        Text(
                            line,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                    }
                }
            }
        }
    }
}
