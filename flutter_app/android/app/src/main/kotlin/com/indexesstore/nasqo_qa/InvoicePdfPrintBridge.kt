package com.indexesstore.nasqo_qa

import android.app.Activity
import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Explicit system dialog only. No network, automatic print, or job-success claim. */
class InvoicePdfPrintBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.indexesstore.nasqo_qa/invoice_pdf_print")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var busy = false
    @Volatile private var disposed = false
    private var active: InvoiceAdapter? = null
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "openPrintDialog") {
                result.notImplemented()
            } else if (disposed || activity.isFinishing || activity.isDestroyed) {
                result.error("PRINT_UNAVAILABLE", "Print activity unavailable.", null)
            } else if (busy) {
                result.error("PRINT_BUSY", "A print dialog is already active.", null)
            } else {
                val bytes = (call.arguments as? Map<*, *>)?.get("bytes") as? ByteArray
                if (bytes == null || bytes.size < 5 || bytes.size > 16 * 1024 * 1024 ||
                    !bytes.copyOfRange(0, 5).contentEquals(byteArrayOf(37, 80, 68, 70, 45))) {
                    result.error("PRINT_INVALID", "Invalid PDF input.", null)
                } else {
                    busy = true
                    pending = result
                    worker.execute {
                        var file: File? = null
                        try {
                            file = File.createTempFile("invoice-print-", ".pdf", activity.cacheDir)
                            file.outputStream().use { it.write(bytes) }
                            val pages = PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { it.pageCount }
                            require(pages in 1..1000) { "Unsupported page count" }
                            val ready = requireNotNull(file)
                            main.post {
                                if (disposed || activity.isFinishing || activity.isDestroyed) {
                                    ready.delete()
                                    finishError("PRINT_INTERRUPTED", "Print request interrupted.")
                                } else {
                                    try {
                                        val manager = activity.getSystemService(Context.PRINT_SERVICE) as? PrintManager
                                            ?: throw IllegalStateException("No print service")
                                        val adapter = InvoiceAdapter(ready, pages)
                                        active = adapter
                                        val attributes = PrintAttributes.Builder()
                                            .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                                            .setColorMode(PrintAttributes.COLOR_MODE_MONOCHROME)
                                            .build()
                                        val job = manager.print("NASQO invoice", adapter, attributes)
                                        if (job == null) throw IllegalStateException("No print dialog")
                                        // A request, not completion or approval of a print job.
                                        pending?.success(true)
                                        pending = null
                                    } catch (_: Exception) {
                                        active = null
                                        ready.delete()
                                        finishError("PRINT_UNAVAILABLE", "Could not open print dialog.")
                                    }
                                }
                            }
                        } catch (_: Exception) {
                            file?.delete()
                            main.post { finishError("PRINT_INVALID", "Could not read generated PDF.") }
                        }
                    }
                }
            }
        }
    }

    private fun finishError(code: String, message: String) {
        pending?.error(code, message, null)
        pending = null
        busy = false
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        finishError("PRINT_INTERRUPTED", "Print activity closed.")
        active?.cleanup()
        active = null
        worker.shutdown()
    }

    private inner class InvoiceAdapter(private val file: File, private val count: Int) : PrintDocumentAdapter() {
        @Volatile private var finished = false
        override fun onLayout(oldAttributes: PrintAttributes?, newAttributes: PrintAttributes,
            cancellationSignal: CancellationSignal, callback: LayoutResultCallback, extras: Bundle?) {
            if (cancellationSignal.isCanceled || finished || disposed) {
                callback.onLayoutCancelled()
                return
            }
            callback.onLayoutFinished(PrintDocumentInfo.Builder("invoice.pdf")
                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).setPageCount(count).build(),
                oldAttributes != newAttributes)
        }

        override fun onWrite(pages: Array<out PageRange>, destination: ParcelFileDescriptor,
            cancellationSignal: CancellationSignal, callback: WriteResultCallback) {
            if (cancellationSignal.isCanceled || finished || disposed) {
                destination.close()
                callback.onWriteCancelled()
                return
            }
            // Never send unrequested pages. Vector PDF is preserved only when
            // every original page was requested; partial ranges fail clearly.
            if (!(0 until count).all { page -> pages.any { page >= it.start && page <= it.end } }) {
                destination.close()
                callback.onWriteFailed("طباعة صفحات محددة غير مدعومة؛ اختر جميع الصفحات.")
                return
            }
            worker.execute {
                var cancelled = false
                var failed = false
                try {
                    ParcelFileDescriptor.AutoCloseOutputStream(destination).use { output ->
                        file.inputStream().use { input ->
                            val buffer = ByteArray(32768)
                            while (true) {
                                if (cancellationSignal.isCanceled || finished || disposed) { cancelled = true; break }
                                val n = input.read(buffer)
                                if (n < 0) break
                                output.write(buffer, 0, n)
                            }
                            output.flush()
                        }
                    }
                } catch (_: Exception) { failed = true }
                main.post {
                    when {
                        cancelled || cancellationSignal.isCanceled || finished || disposed -> callback.onWriteCancelled()
                        failed -> callback.onWriteFailed("تعذر تجهيز ملف الطباعة.")
                        else -> callback.onWriteFinished(arrayOf(PageRange(0, count - 1)))
                    }
                }
            }
        }

        fun cleanup() { finished = true; file.delete() }
        override fun onFinish() {
            cleanup()
            if (active === this) { active = null; busy = false }
        }
    }
}
