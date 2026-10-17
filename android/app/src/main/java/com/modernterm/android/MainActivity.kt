package com.modernterm.android
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.*
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState)
        setContent { MaterialTheme { Surface(Modifier.fillMaxSize()) { Column { Text("ModernTerm · Android validation")
            AndroidView(factory={ TerminalPane(it, {}, {_,_->}).apply { onReady = { write("ModernTerm — 终端输入验证\r\n".toByteArray()); showKeyboard() } } },modifier=Modifier.weight(1f))
        } } } }
    }
}
