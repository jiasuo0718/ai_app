package com.acevm.vmm

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import com.acevm.vmm.ui.MainScreen
import com.acevm.vmm.vm.AppContextHolder
import com.acevm.vmm.vm.VmViewModel

class MainActivity : ComponentActivity() {

    private val vm: VmViewModel by viewModels {
        VmViewModel.Factory
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppContextHolder.init(applicationContext)
        setContent {
            MaterialTheme {
                MainScreen(vm)
            }
        }
    }
}
