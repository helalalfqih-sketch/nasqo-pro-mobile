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
        HybridHomeView(context, messenger, viewId, activity, (args as? Map<*, *>)?.get("reactWorkspace") == true)
}

private class HybridHomeView(context: Context, messenger: BinaryMessenger, id: Int, activity: Activity, private val reactWorkspace: Boolean) : PlatformView {
    private val web = WebView(context)
    private val channel = MethodChannel(messenger, "nasqo/home/$id")
    private val origin = Uri.parse("https://appassets.androidplatform.net")
    private val page = if (reactWorkspace) "$origin/react/index.html" else "$origin/home/index.html"
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
        val loaderBuilder = WebViewAssetLoader.Builder().addPathHandler("/home/") { path ->
            resources[path]?.let { (mime, file) ->
                WebResourceResponse(mime, if (mime.startsWith("text/") || path == "home.js") "utf-8" else null,
                    context.assets.open(file))
            }
        }
        if (reactWorkspace) {
            // Permit Chromium DevTools only on disposable Android emulators
            // for signed QA Release smoke tests. Never enable on real devices.
            val emulatorForQa = android.os.Build.TYPE != "user" &&
                (android.os.Build.FINGERPRINT.startsWith("generic") ||
                 android.os.Build.FINGERPRINT.contains("emulator") ||
                 android.os.Build.PRODUCT.contains("sdk"))
            if ((context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0 ||
                emulatorForQa) {
                WebView.setWebContentsDebuggingEnabled(true)
            }
            val assetPattern = Regex("assets/[A-Za-z0-9_.-]+")
            val mimeTypes = mapOf("html" to "text/html", "js" to "text/javascript", "css" to "text/css",
                "png" to "image/png", "woff" to "font/woff", "woff2" to "font/woff2")
            loaderBuilder.addPathHandler("/react/") { path ->
                val mime = mimeTypes[path.substringAfterLast('.')]
                if (mime == null || !(path == "index.html" || assetPattern.matches(path))) null
                else try {
                    val encoding = if (mime.startsWith("text/")) "utf-8" else null
                    WebResourceResponse(mime, encoding, context.assets.open("flutter_assets/assets/react/$path"))
                } catch (_: java.io.IOException) { null }
            }
        }
        val loader = loaderBuilder.build()
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = reactWorkspace
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
                                _, message, sender, mainFrame, reply ->
                                if (mainFrame && sender == origin && message.type == WebMessageCompat.TYPE_STRING) {
                                    val data = message.data
                                    if (reactWorkspace && data != null && data.length <= 262144) {
                                        channel.invokeMethod("reactRequest", data, object : MethodChannel.Result {
                                            override fun success(result: Any?) {
                                                if (started && result is String) reply.postMessage(result)
                                            }
                                            override fun error(code: String, message: String?, details: Any?) = Unit
                                            override fun notImplemented() = Unit
                                        })
                                    } else if (!reactWorkspace && data != null && data.length <= 4096) {
                                        channel.invokeMethod("intent", data)
                                    }
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
                "printDirectory", "printDocument" -> {
                    try {
                        val job = if (call.method == "printDocument") "NASQO - مستند" else "NASQO - كشف الحسابات"
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
        started = false
        web.stopLoading()
        web.destroy()
    }
}
