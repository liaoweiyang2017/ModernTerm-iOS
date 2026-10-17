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
                        loaded = true
                        write(pending.toByteArray())
                        pending.reset()
                        onReady?.invoke()
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
        if (loaded) evaluateJavascript("appearance($theme,$size)", null)
    }

    fun showKeyboard() {
        requestFocus()
        evaluateJavascript("focusInput()", null)
        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .showSoftInput(this, InputMethodManager.SHOW_IMPLICIT)
    }

    fun hideKeyboard() {
        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .hideSoftInputFromWindow(windowToken, 0)
        clearFocus()
    }

    override fun destroy() {
        removeJavascriptInterface("Bridge")
        super.destroy()
    }
}
