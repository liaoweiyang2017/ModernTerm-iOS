package com.modernterm.android

import android.annotation.SuppressLint
import android.content.Context
import android.view.inputmethod.InputMethodManager
import android.webkit.*
import androidx.webkit.WebViewAssetLoader
import java.util.Base64
import org.json.JSONObject

@SuppressLint("SetJavaScriptEnabled")
class TerminalPane(
    context: Context,
    private val input: (String) -> Unit,
    private val resized: (Int, Int) -> Unit,
    private val directory: (String) -> Unit = {},
) : WebView(context) {
    private var loaded = false
    private var keyboardRequested = false
    private var lastAppearance: String? = null
    private val taps =
        android.view.GestureDetector(
            context,
            object : android.view.GestureDetector.SimpleOnGestureListener() {
                override fun onSingleTapUp(event: android.view.MotionEvent): Boolean {
                    showKeyboard()
                    return false
                }
            },
        )
    private var disposed = false
    val isReady: Boolean
        get() = loaded

    var loadFailure: String? = null
        private set

    private val pending = java.io.ByteArrayOutputStream()
    var onReady: (() -> Unit)? = null

    init {
        layoutParams =
            android.view.ViewGroup.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            )
        settings.javaScriptEnabled = true
        settings.textZoom = 100
        settings.setSupportZoom(false)
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        settings.domStorageEnabled = false
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        isFocusableInTouchMode = true
        webChromeClient =
            object : WebChromeClient() {
                override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                    if (
                        message.messageLevel() == ConsoleMessage.MessageLevel.ERROR &&
                            loadFailure == null &&
                            !message.message().contains("favicon")
                    ) {
                        loadFailure =
                            "Renderer error at ${message.sourceId().substringAfterLast('/')}:${message.lineNumber()}: ${message.message().take(160)}"
                    }
                    return true
                }
            }
        val loader =
            WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
                .build()
        webViewClient =
            object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) =
                    true

                override fun shouldInterceptRequest(
                    view: WebView,
                    request: WebResourceRequest,
                ): WebResourceResponse? =
                    loader.shouldInterceptRequest(request.url)
                        ?: WebResourceResponse(
                            "text/plain",
                            "UTF-8",
                            403,
                            "Blocked",
                            emptyMap(),
                            ByteArray(0).inputStream(),
                        )
            }
        addJavascriptInterface(
            object {
                @JavascriptInterface
                fun input(value: String) {
                    if (value.length <= 65536) this@TerminalPane.input(value)
                }

                @JavascriptInterface
                fun resize(cols: Int, rows: Int) {
                    if (cols in 1..1000 && rows in 1..1000) resized(cols, rows)
                }

                @JavascriptInterface
                fun directory(value: String) {
                    if (value.length <= 4096) this@TerminalPane.directory(value)
                }

                @JavascriptInterface
                fun ready() {
                    post {
                        if (disposed) return@post
                        loaded = true
                        write(pending.toByteArray())
                        pending.reset()
                        onReady?.invoke()
                        if (keyboardRequested) showKeyboard()
                    }
                }
            },
            "Bridge",
        )
        loadUrl("https://appassets.androidplatform.net/assets/terminal/index.html")
    }

    fun write(bytes: ByteArray) {
        if (bytes.isEmpty()) return
        if (!loaded) {
            if (pending.size() + bytes.size <= 262144) pending.write(bytes)
            return
        }
        evaluateJavascript(
            "feed(${JSONObject.quote(Base64.getEncoder().encodeToString(bytes))})",
            null,
        )
    }

    fun setAppearance(theme: JSONObject, size: Int) {
        val value = "$theme,$size"
        if (loaded && value != lastAppearance) {
            lastAppearance = value
            evaluateJavascript("appearance($value)", null)
        }
    }

    override fun onTouchEvent(event: android.view.MotionEvent): Boolean {
        taps.onTouchEvent(event)
        return super.onTouchEvent(event)
    }

    fun showKeyboard() {
        keyboardRequested = true
        if (!loaded || disposed) return
        requestFocus()
        // WebView's editor connection is ready only after the DOM textarea is focused.
        evaluateJavascript("focusInput()") {
            post {
                if (!disposed && keyboardRequested && hasWindowFocus()) {
                    (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                        .showSoftInput(this, InputMethodManager.SHOW_IMPLICIT)
                }
            }
        }
    }

    fun hideKeyboard() {
        keyboardRequested = false
        if (loaded && !disposed) evaluateJavascript("term.blur()", null)
        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .hideSoftInputFromWindow(windowToken, 0)
        clearFocus()
    }

    fun copyAll() {
        evaluateJavascript(
            "(()=>{term.selectAll();const text=term.getSelection();term.clearSelection();return text})()"
        ) { value ->
            runCatching {
                val text = org.json.JSONArray("[$value]").getString(0)
                val clipboard =
                    context.getSystemService(Context.CLIPBOARD_SERVICE)
                        as android.content.ClipboardManager
                clipboard.setPrimaryClip(
                    android.content.ClipData.newPlainText("Terminal output", text)
                )
            }
        }
    }

    fun pasteClipboard() {
        val clipboard =
            context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString() ?: return
        if (text.length <= 65536) evaluateJavascript("term.paste(${JSONObject.quote(text)})", null)
    }

    override fun destroy() {
        disposed = true
        onReady = null
        pending.reset()
        removeJavascriptInterface("Bridge")
        super.destroy()
    }
}
