package com.indexesstore.nasqo_qa

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.webkit.PermissionRequest
import android.webkit.ValueCallback
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private data class CsvRequest(val bytes: ByteArray, val result: MethodChannel.Result)

    private val writer = Executors.newSingleThreadExecutor()
    private var pending: CsvRequest? = null
    private var writing = false
    private var csvChannel: MethodChannel? = null
    private var invoicePrinter: InvoicePdfPrintBridge? = null
    private var devUpdateBridge: DevUpdateBridge? = null
    private var pendingQrCamera: PermissionRequest? = null
    private var pendingQrImage: ValueCallback<Array<Uri>>? = null

    internal fun requestReactQrCamera(request: PermissionRequest) {
        if (isFinishing || isDestroyed) {
            request.deny()
            return
        }
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            request.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE))
            return
        }
        if (pendingQrCamera != null) {
            request.deny()
            return
        }
        pendingQrCamera = request
        requestPermissions(arrayOf(Manifest.permission.CAMERA), QR_CAMERA_PERMISSION)
    }

    internal fun cancelReactQrCamera(request: PermissionRequest) {
        if (pendingQrCamera === request) pendingQrCamera = null
    }

    internal fun openReactQrImagePicker(callback: ValueCallback<Array<Uri>>) {
        if (pendingQrImage != null) {
            callback.onReceiveValue(null)
            return
        }
        pendingQrImage = callback
        val chooser = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(chooser, QR_IMAGE_PICKER)
        } catch (_: Exception) {
            pendingQrImage = null
            callback.onReceiveValue(null)
        }
    }

    @Deprecated("Android permissions compatibility callback")
    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != QR_CAMERA_PERMISSION) return
        val request = pendingQrCamera ?: return
        pendingQrCamera = null
        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            request.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE))
        } else {
            request.deny()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "nasqo/offline-home", HybridHomeFactory(flutterEngine.dartExecutor.binaryMessenger, this)
        )
        invoicePrinter = InvoicePdfPrintBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        devUpdateBridge = DevUpdateBridge(this, flutterEngine.dartExecutor.binaryMessenger)
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
        if (requestCode == QR_IMAGE_PICKER) {
            val callback = pendingQrImage
            pendingQrImage = null
            val uri = data?.data
            callback?.onReceiveValue(
                if (resultCode == Activity.RESULT_OK && uri?.scheme == "content") arrayOf(uri)
                else null
            )
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
        pendingQrCamera?.deny()
        pendingQrCamera = null
        pendingQrImage?.onReceiveValue(null)
        pendingQrImage = null
        devUpdateBridge?.dispose()
        devUpdateBridge = null
        invoicePrinter?.dispose()
        invoicePrinter = null
        val request = pending
        pending = null
        request?.result?.error("EXPORT_INTERRUPTED", "Export was interrupted.", null)
        csvChannel?.setMethodCallHandler(null)
        csvChannel = null
        writer.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.indexesstore.nasqo_qa/csv_export"
        private const val CREATE_CSV = 28714
        private const val QR_CAMERA_PERMISSION = 28716
        private const val QR_IMAGE_PICKER = 28717
        private const val CSV_LIMIT = 8 * 1024 * 1024
        private val BACKUP_NAME = Regex("^nasqo-[0-9]{13,18}-[0-9a-f]{24}\\.json$")
        private val FILE_NAME = Regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,95}\\.csv$")
    }
}
