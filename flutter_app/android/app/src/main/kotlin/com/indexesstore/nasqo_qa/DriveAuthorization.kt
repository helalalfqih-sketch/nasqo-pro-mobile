package com.indexesstore.nasqo_qa

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Only Dart can call this channel. Neither credentials nor Drive file contents
 * are delivered to the WebView. Consent is always owned by Google Play services. */
class DriveAuthorization(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.indexesstore.nasqo_qa/drive")
    private val client = Identity.getAuthorizationClient(activity)
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "authorize") {
                result.notImplemented()
            } else if (pending != null) {
                result.error("BUSY", "Google consent is already open.", null)
            } else {
                pending = result
                val request = AuthorizationRequest.builder()
                    .setRequestedScopes(listOf(Scope("https://www.googleapis.com/auth/drive.file")))
                    .build()
                client.authorize(request).addOnSuccessListener { auth ->
                    if (pending !== result) return@addOnSuccessListener
                    val resolution = auth.pendingIntent
                    if (auth.hasResolution() && resolution != null) {
                        try {
                            activity.startIntentSenderForResult(resolution.intentSender, REQUEST, null, 0, 0, 0)
                        } catch (_: IntentSender.SendIntentException) {
                            fail("AUTH_UNAVAILABLE")
                        }
                    } else {
                        complete(auth.accessToken)
                    }
                }.addOnFailureListener { if (pending === result) fail("AUTH_UNAVAILABLE") }
            }
        }
    }

    fun onResult(code: Int, result: Int, data: Intent?): Boolean {
        if (code != REQUEST) return false
        if (result != Activity.RESULT_OK || data == null) fail("CANCELLED")
        else try { complete(client.getAuthorizationResultFromIntent(data).accessToken) }
        catch (_: Exception) { fail("AUTH_UNAVAILABLE") }
        return true
    }

    private fun complete(token: String?) {
        if (token.isNullOrBlank()) { fail("AUTH_UNAVAILABLE"); return }
        val target = pending
        pending = null
        target?.success(token)
    }

    private fun fail(code: String) {
        val target = pending
        pending = null
        target?.error(code, "Drive authorization did not complete.", null)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        fail("CANCELLED")
    }

    companion object { private const val REQUEST = 28718 }
}
