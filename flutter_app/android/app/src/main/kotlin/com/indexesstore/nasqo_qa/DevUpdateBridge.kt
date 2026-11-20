package com.indexesstore.nasqo_qa

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DevUpdateBridge(private val activity: FlutterActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.indexesstore.nasqo_qa/dev_updates")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "install") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val cache = activity.cacheDir.canonicalFile
            val file = path?.let { File(it).canonicalFile }
            if (file == null || file.parentFile != cache ||
                file.name != "nasqo-dev-update.apk" || !file.isFile) {
                result.error("INVALID_APK", "Invalid update path", null)
                return@setMethodCallHandler
            }
            try {
                val uri: Uri = FileProvider.getUriForFile(
                    activity, "${activity.packageName}.devupdates", file)
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivity(intent)
                result.success(null)
            } catch (_: ActivityNotFoundException) {
                result.error("NO_INSTALLER", "Android installer unavailable", null)
            } catch (_: SecurityException) {
                result.error("INSTALL_DENIED", "Installer permission denied", null)
            } catch (_: IllegalArgumentException) {
                result.error("INVALID_URI", "Invalid APK file", null)
            }
        }
    }
    fun dispose() { channel.setMethodCallHandler(null) }
}
