package com.indexesstore.nasqo_qa

import android.app.Activity
import android.content.Intent
import android.content.Context
import android.net.Uri
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.webkit.WebMessage
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream

class HybridHomeFactory(private val messenger: BinaryMessenger, private val activity: Activity) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        HybridHomeView(context, messenger, viewId, activity)
}

private class HybridHomeView(context: Context, messenger: BinaryMessenger, id: Int, activity: Activity) : PlatformView {
    private val web = WebView(context)
    private val channel = MethodChannel(messenger, "nasqo/home/$id")
    private val origin = Uri.parse("https://appassets.androidplatform.net")
    private val page = "$origin/home/index.html"
    private val created = SystemClock.elapsedRealtime()
    private var started = false
    private var painted = false

    init {
        val assets = mapOf(
            "index.html" to Pair("text/html", "hybrid_home/index.html"),
            "home.js" to Pair("application/javascript", "hybrid_home/home.js"),
            "home.css" to Pair("text/css", "hybrid_home/home.css"),
            "logo.png" to Pair("image/png", "flutter_assets/assets/nasqo_logo.png"),
            "arabic.ttf" to Pair("font/ttf", "flutter_assets/assets/fonts/NotoSansArabic-Regular.ttf"),
        )
        val fontFiles = listOf("Regular", "Medium", "SemiBold", "Bold").associate {
            val name = "fonts/IBMPlexSansArabic-$it.ttf"
            name to Pair("font/ttf", "hybrid_home/$name")
        }
        val resources = assets + fontFiles
        val loader = WebViewAssetLoader.Builder().addPathHandler("/home/") { path ->
            resources[path]?.let { (mime, file) ->
                WebResourceResponse(mime, if (mime.startsWith("text/") || path == "home.js") "utf-8" else null,
                    context.assets.open(file))
            }
        }.build()
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = false
            allowFileAccess = false
            allowContentAccess = false
            blockNetworkLoads = true
            javaScriptCanOpenWindowsAutomatically = false
            mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse =
                if (request.method == "GET") loader.shouldInterceptRequest(request.url) ?: denied() else denied()

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true

            @Deprecated("Needed on Android 6")
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean = true
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
                        result.error("WEBVIEW_UNSUPPORTED", "Unsupported local message channel", null)
                    } else {
                        if (!started) {
                            started = true
                            WebViewCompat.addWebMessageListener(web, "NasqoHome", setOf(origin.toString())) {
                                _, message, sender, mainFrame, _ ->
                                if (mainFrame && sender == origin && message.type == WebMessageCompat.TYPE_STRING) {
                                    val data = message.data
                                    if (data != null && data.length <= 4096) channel.invokeMethod("intent", data)
                                }
                            }
                            web.loadUrl(page)
                        }
                        result.success(null)
                    }
                }
                "present" -> {
                    val payload = call.arguments as? String
                    if (!started || payload == null) result.error("NOT_READY", "Local view unavailable", null)
                    else {
                        web.postWebMessage(WebMessage(payload), origin)
                        result.success(null)
                    }
                }
                "printDirectory" -> {
                    try {
                        val job = "NASQO - كشف الحسابات"
                        val printer = activity.getSystemService(Context.PRINT_SERVICE) as android.print.PrintManager
                        printer.print(job, web.createPrintDocumentAdapter(job), null)
                        result.success(null)
                    } catch (_: RuntimeException) {
                        result.error("PRINT_UNAVAILABLE", "Print dialog unavailable", null)
                    }
                }
                "contact" -> {
                    val phone = call.argument<String>("phone").orEmpty()
                    val text = call.argument<String>("text").orEmpty()
                    val intent = when (call.argument<String>("op")) {
                        "contact" -> if (phone.isBlank()) null else Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", phone, null))
                        "message" -> Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null)
                        "whatsapp" -> if (phone.isBlank()) null else Intent(Intent.ACTION_VIEW,
                            Uri.Builder().scheme("https").authority("wa.me").appendPath(phone.filter(Char::isDigit))
                                .appendQueryParameter("text", text).build()).setPackage("com.whatsapp")
                        else -> null
                    }
                    if (intent == null) result.error("NO_CONTACT", "Missing contact details", null)
                    else try {
                        activity.startActivity(intent)
                        result.success(null)
                    } catch (_: android.content.ActivityNotFoundException) {
                        result.error("UNAVAILABLE", "No matching Android activity", null)
                    }
                }
                "endEdit" -> { web.evaluateJavascript("window.nasqoBack()", null); result.success(null) }
                "top" -> { web.evaluateJavascript("window.nasqoTop()", null); result.success(null) }
                "paint" -> {
                    if (!painted) {
                        painted = true
                        Log.i("NasqoHybrid", "home_paint_ms=" + (SystemClock.elapsedRealtime() - created))
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun denied() = WebResourceResponse("text/plain", "utf-8", 403, "Forbidden",
        emptyMap(), ByteArrayInputStream(byteArrayOf()))

    override fun getView(): View = web
    override fun dispose() {
        channel.setMethodCallHandler(null)
        if (started) WebViewCompat.removeWebMessageListener(web, "NasqoHome")
        web.stopLoading()
        web.destroy()
    }
}
