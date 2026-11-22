package com.indexesstore.nasqo_qa

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Handler
import android.os.Looper
import java.io.File
import java.security.SecureRandom
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private data class CsvRequest(val bytes: ByteArray, val result: MethodChannel.Result)

    private val writer = Executors.newSingleThreadExecutor()
    private var pending: CsvRequest? = null
    private var writing = false
    private var importPending: MethodChannel.Result? = null
    private var importChannel: MethodChannel? = null
    private var csvChannel: MethodChannel? = null
    private var invoicePrinter: InvoicePdfPrintBridge? = null
    private var devUpdateBridge: DevUpdateBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "nasqo/offline-home", HybridHomeFactory(flutterEngine.dartExecutor.binaryMessenger, this)
        )
        invoicePrinter = InvoicePdfPrintBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        devUpdateBridge = DevUpdateBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IMPORT_CHANNEL)
        importChannel?.setMethodCallHandler { call, result ->
            if (call.method != "selectWebsiteBackup") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (importPending != null) {
                result.error("IMPORT_BUSY", "File selection already in progress", null)
                return@setMethodCallHandler
            }
            importPending = result
            val chooser = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
            }
            try {
                @Suppress("DEPRECATION")
                startActivityForResult(chooser, OPEN_WEBSITE_BACKUP)
            } catch (_: Exception) {
                importPending = null
                result.error("IMPORT_PICKER_UNAVAILABLE", "Android file picker unavailable", null)
            }
        }
        csvChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        csvChannel?.setMethodCallHandler { call, result ->
            val report = call.method == "saveReport"
            val backup = report || call.method == "saveBackup"
            if (!backup && call.method != "saveCsv") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pending != null) {
                result.error("EXPORT_BUSY", "Another export is in progress.", null)
                return@setMethodCallHandler
            }
            val arguments = call.arguments as? Map<*, *>
            val bytes = arguments?.get("bytes") as? ByteArray
            val name = arguments?.get("suggestedName") as? String
            val limit = if (backup) 16 * 1024 * 1024 else CSV_LIMIT
            val pattern = if (report) Regex("nasqo-inspection[.]json") else if (backup) BACKUP_NAME else FILE_NAME
            if (bytes == null || bytes.isEmpty() || bytes.size > limit ||
                name == null || !pattern.matches(name)
            ) {
                result.error("EXPORT_INVALID", "Invalid export.", null)
                return@setMethodCallHandler
            }

            pending = CsvRequest(bytes, result)
            val chooser = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = if (backup) "application/json" else "text/csv"
                putExtra(Intent.EXTRA_TITLE, name)
                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
            }
            try {
                @Suppress("DEPRECATION")
                startActivityForResult(chooser, CREATE_CSV)
            } catch (_: ActivityNotFoundException) {
                pending = null
                result.error("EXPORT_PICKER_MISSING", "No file picker available.", null)
            } catch (_: SecurityException) {
                pending = null
                result.error("EXPORT_PICKER_DENIED", "File picker unavailable.", null)
            }
        }
    }

    @Deprecated("Activity result bridge for FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == OPEN_WEBSITE_BACKUP) {
            val request = importPending ?: return
            importPending = null
            if (resultCode == Activity.RESULT_CANCELED) {
                request.success(null)
                return
            }
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null || uri.scheme != "content") {
                request.error("IMPORT_INVALID_URI", "Only Android content URIs are accepted", null)
                return
            }
            writer.execute {
                var target: File? = null
                try {
                    val folder = File(cacheDir, "nasqo-website-import")
                    if (!folder.exists() && !folder.mkdirs()) throw IllegalStateException("No private cache")
                    val random = ByteArray(16)
                    SecureRandom().nextBytes(random)
                    val token = random.joinToString("") { "%02x".format(it) }
                    target = File(folder, "$token.bin")
                    var total = 0L
                    contentResolver.openInputStream(uri)?.use { source ->
                        target!!.outputStream().use { output ->
                            val buffer = ByteArray(65536)
                            while (true) {
                                val n = source.read(buffer)
                                if (n < 0) break
                                total += n
                                if (total > IMPORT_LIMIT) throw IllegalArgumentException("File exceeds limit")
                                output.write(buffer, 0, n)
                            }
                        }
                    } ?: throw IllegalStateException("File unavailable")
                    if (total == 0L) throw IllegalArgumentException("Empty file")
                    Handler(Looper.getMainLooper()).post {
                        request.success(mapOf("token" to token, "sizeBytes" to total))
                    }
                } catch (_: Exception) {
                    target?.delete()
                    Handler(Looper.getMainLooper()).post {
                        request.error("IMPORT_READ_FAILED", "Could not read the selected backup", null)
                    }
                }
            }
            return
        }
        if (requestCode != CREATE_CSV || writing) return
        val request = pending ?: return
        if (resultCode == Activity.RESULT_CANCELED) {
            pending = null
            request.result.success(false)
            return
        }
        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null || destination.scheme != "content") {
            pending = null
            request.result.error("EXPORT_DESTINATION", "No chosen file destination.", null)
            return
        }

        writing = true
        writer.execute {
            val success = try {
                val stream = contentResolver.openOutputStream(destination, "wt")
                    ?: throw IllegalStateException("No output stream.")
                stream.use {
                    it.write(request.bytes)
                    it.flush()
                }
                true
            } catch (_: Exception) {
                false
            }
            runOnUiThread {
                writing = false
                if (pending === request) {
                    pending = null
                    if (success) request.result.success(true)
                    else request.result.error("EXPORT_FAILED", "Could not confirm file save.", null)
                }
            }
        }
    }

    override fun onDestroy() {
        devUpdateBridge?.dispose()
        devUpdateBridge = null
        invoicePrinter?.dispose()
        invoicePrinter = null
        val request = pending
        pending = null
        request?.result?.error("EXPORT_INTERRUPTED", "Export was interrupted.", null)
        importPending?.error("IMPORT_INTERRUPTED", "Picker was interrupted", null)
        importPending = null
        importChannel?.setMethodCallHandler(null)
        importChannel = null
        csvChannel?.setMethodCallHandler(null)
        csvChannel = null
        writer.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.indexesstore.nasqo_qa/csv_export"
        private const val IMPORT_CHANNEL = "com.indexesstore.nasqo_qa/website_import"
        private const val OPEN_WEBSITE_BACKUP = 28715
        private const val IMPORT_LIMIT = 32L * 1024 * 1024
        private const val CREATE_CSV = 28714
        private const val CSV_LIMIT = 8 * 1024 * 1024
        private val BACKUP_NAME = Regex("^nasqo-[0-9]{13,18}-[0-9a-f]{24}\\.json$")
        private val FILE_NAME = Regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,95}\\.csv$")
    }
}
