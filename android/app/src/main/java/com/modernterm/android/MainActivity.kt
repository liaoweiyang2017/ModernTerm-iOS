package com.modernterm.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner

class MainActivity : ComponentActivity() {
    internal val workspace: Workspace by viewModels()
    private val observer =
        object : DefaultLifecycleObserver {
            override fun onStop(owner: LifecycleOwner) {
                workspace.background()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        ProcessLifecycleOwner.get().lifecycle.addObserver(observer)
        setContent { ModernTermApp(workspace) }
    }

    override fun onDestroy() {
        ProcessLifecycleOwner.get().lifecycle.removeObserver(observer)
        super.onDestroy()
    }
}
