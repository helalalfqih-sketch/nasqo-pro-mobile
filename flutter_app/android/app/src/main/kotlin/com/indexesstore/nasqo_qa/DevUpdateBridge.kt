package com.indexesstore.nasqo_qa

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class DevUpdateBridge(private val activity: FlutterActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.indexesstore.nasqo_qa/dev_updates")
    private val verifier = Executors.newSingleThreadExecutor()
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "install") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val code = call.argument<Number>("versionCode")?.toLong()
            if (path == null || code == null || code < 1) {
                result.error("INVALID_APK", "بيانات التحديث غير صالحة.", null)
                return@setMethodCallHandler
            }
            verifier.execute {
                val file = try {
                    val cache = File(activity.cacheDir, "dev-updates").canonicalFile
                    val candidate = File(path).canonicalFile
                    candidate.takeIf {
                        it.parentFile == cache && it.isFile &&
                            Regex("nasqo-$code-[a-f0-9]{64}\\.apk").matches(it.name) &&
                            matchesInstalledApp(it, code)
                    }
                } catch (_: Exception) {
                    null
                }
                activity.runOnUiThread {
                    if (disposed) return@runOnUiThread
                    if (file == null) {
                        result.error("INVALID_APK", "تعذّر التحقق من هوية التطبيق أو توقيعه أو رقم إصداره.", null)
                    } else {
                        openInstaller(file, result)
                    }
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun matchesInstalledApp(file: File, expectedCode: Long): Boolean {
        val pm = activity.packageManager
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
                    else PackageManager.GET_SIGNATURES
        val installed = pm.getPackageInfo(activity.packageName, flags)
        val candidate = pm.getPackageArchiveInfo(file.path, flags) ?: return false
        val installedSigners = signers(installed)
        return candidate.packageName == activity.packageName &&
            version(candidate) == expectedCode && expectedCode > version(installed) &&
            installedSigners.isNotEmpty() && signers(candidate) == installedSigners
    }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<Signature> =
        if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners?.toSet().orEmpty()
        else info.signatures?.toSet().orEmpty()

    @Suppress("DEPRECATION")
    private fun version(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    private fun openInstaller(file: File, result: MethodChannel.Result) {
        try {
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.devupdates", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                clipData = ClipData.newUri(activity.contentResolver, "NASQO update", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(intent)
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("NO_INSTALLER", "مثبّت أندرويد غير متاح.", null)
        } catch (_: SecurityException) {
            result.error("INSTALL_DENIED", "لم يسمح أندرويد بفتح المثبّت.", null)
        } catch (_: RuntimeException) {
            // Some AndroidX FileProvider builds throw StringIndexOutOfBoundsException
            // while resolving a misconfigured path. Report safely to Flutter.
            result.error("INVALID_URI", "تعذّر تجهيز ملف التحديث للمثبّت. جرّب مرة أخرى.", null)
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        verifier.shutdown()
    }
}
