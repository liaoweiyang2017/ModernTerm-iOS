package com.modernterm.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.*

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
        if (savedInstanceState == null) receiveAttachment(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receiveAttachment(intent)
    }

    private fun receiveAttachment(intent: Intent) {
        if (
            intent.action !in
                listOf(Intent.ACTION_VIEW, Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)
        )
            return
        if (
            workspace.transferOpen ||
                workspace.receivingFile ||
                workspace.incomingFiles.isNotEmpty()
        ) {
            workspace.incomingError =
                "Finish or cancel the current transfer, then open the attachment again."
            return
        }
        workspace.receivingFile = true
        lifecycleScope.launch {
            try {
                val uris = TermIncomingFiles.uris(intent)
                workspace.incomingFiles =
                    withContext(Dispatchers.IO) { TermIncomingFiles.read(this@MainActivity, uris) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                workspace.incomingError = e.message ?: "Could not read attachment."
            } finally {
                workspace.receivingFile = false
            }
        }
    }

    override fun onDestroy() {
        ProcessLifecycleOwner.get().lifecycle.removeObserver(observer)
        super.onDestroy()
    }
}
