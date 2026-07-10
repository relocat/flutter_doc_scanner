package com.shirsh.flutter_doc_scanner


import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import android.util.Log
import androidx.core.app.ActivityCompat.startIntentSenderForResult
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.io.File
import java.io.IOException

class FlutterDocScannerPlugin : MethodCallHandler, ActivityResultListener,
    FlutterPlugin, ActivityAware {
    private var channel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val CHANNEL = "flutter_doc_scanner"
    private var activity: Activity? = null
    private var applicationContext: Context? = null
    private var pendingResult: MethodChannel.Result? = null

    private val REQUEST_CODE_SCAN = 213312
    private val REQUEST_CODE_SCAN_URI = 214412
    private val REQUEST_CODE_SCAN_IMAGES = 215512
    private val REQUEST_CODE_SCAN_PDF = 216612
    private val DEFAULT_PAGE_LIMIT = 4
    private val TAG = FlutterDocScannerPlugin::class.java.simpleName

    // Static (no path/URI echo) failure surface for copyPageToFile. The caller
    // owns destPath, so we never validate or reveal it in error output.
    private val ERROR_COPY_FAILED = "COPY_FAILED"
    private val ERROR_COPY_FAILED_MESSAGE = "Failed to copy scanned page."


    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "getScanDocuments" -> startDocumentScan(
                result,
                call.arguments as? Map<*, *>,
                REQUEST_CODE_SCAN,
                intArrayOf(
                    GmsDocumentScannerOptions.RESULT_FORMAT_JPEG,
                    GmsDocumentScannerOptions.RESULT_FORMAT_PDF
                )
            )
            "getScannedDocumentAsImages" -> startDocumentScan(
                result,
                call.arguments as? Map<*, *>,
                REQUEST_CODE_SCAN_IMAGES,
                intArrayOf(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            )
            "getScannedDocumentAsPdf" -> startDocumentScan(
                result,
                call.arguments as? Map<*, *>,
                REQUEST_CODE_SCAN_PDF,
                intArrayOf(GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
            )
            "getScanDocumentsUri" -> startDocumentScan(
                result,
                call.arguments as? Map<*, *>,
                REQUEST_CODE_SCAN_URI,
                intArrayOf(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            )
            "copyPageToFile" -> copyPageToFile(call, result)
            else -> result.notImplemented()
        }
    }

    private fun startDocumentScan(
        result: Result,
        arguments: Map<*, *>?,
        requestCode: Int,
        resultFormats: IntArray
    ) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Document scanner requires a foreground activity.", null)
            return
        }

        if (pendingResult != null) {
            result.error("SCAN_IN_PROGRESS", "Another scan is already running.", null)
            return
        }

        val pageLimit = (arguments?.get("page") as? Int)?.coerceAtLeast(1) ?: DEFAULT_PAGE_LIMIT
        val useAutomaticSinglePictureProcessing =
            (arguments?.get("useAutomaticSinglePictureProcessing") as? Boolean) ?: false
        // New fast path: single page + base scanner mode (page argument is intentionally ignored).
        val fastSinglePageMode =
            requestCode == REQUEST_CODE_SCAN_IMAGES && useAutomaticSinglePictureProcessing
        val effectivePageLimit = if (fastSinglePageMode) 1 else pageLimit
        val scannerMode = if (fastSinglePageMode) {
            GmsDocumentScannerOptions.SCANNER_MODE_BASE
        } else {
            GmsDocumentScannerOptions.SCANNER_MODE_FULL
        }
        val galleryImportAllowed = !fastSinglePageMode

        pendingResult = result
        launchDocumentScanner(
            currentActivity,
            effectivePageLimit,
            requestCode,
            resultFormats,
            scannerMode,
            galleryImportAllowed
        )
    }

    private fun launchDocumentScanner(
        currentActivity: Activity,
        pageLimit: Int,
        requestCode: Int,
        resultFormats: IntArray,
        scannerMode: Int,
        galleryImportAllowed: Boolean
    ) {
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(galleryImportAllowed)
            .setPageLimit(pageLimit)
            .setScannerMode(scannerMode)
        if (resultFormats.isNotEmpty()) {
            val firstFormat = resultFormats.first()
            val remainingFormats = resultFormats.drop(1).toIntArray()
            options.setResultFormats(firstFormat, *remainingFormats)
        }
        val builtOptions = options.build()

        GmsDocumentScanning.getClient(builtOptions)
            .getStartScanIntent(currentActivity)
            .addOnSuccessListener { intentSender: IntentSender ->
                try {
                    startIntentSenderForResult(
                        currentActivity,
                        intentSender,
                        requestCode,
                        null,
                        0,
                        0,
                        0,
                        null
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Unable to launch document scanner", e)
                    finishWithError("Unable to launch document scanner", e)
                }
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Unable to start document scanner", e)
                finishWithError("Unable to start document scanner", e)
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (pendingResult == null) return false

        return when (requestCode) {
            REQUEST_CODE_SCAN, REQUEST_CODE_SCAN_PDF -> {
                handlePdfResult(resultCode, data)
                true
            }

            REQUEST_CODE_SCAN_IMAGES, REQUEST_CODE_SCAN_URI -> {
                handleImageResult(resultCode, data)
                true
            }

            else -> false
        }
    }

    private fun handlePdfResult(resultCode: Int, data: Intent?) {
        when (resultCode) {
            Activity.RESULT_OK -> {
                val pdf = GmsDocumentScanningResult.fromActivityResultIntent(data)?.getPdf()
                if (pdf != null) {
                    finishWithSuccess(
                        mapOf(
                            "pdfUri" to pdf.getUri().toString(),
                            "pageCount" to pdf.getPageCount(),
                        )
                    )
                } else {
                    finishWithError("No PDF result returned")
                }
            }

            Activity.RESULT_CANCELED -> finishWithSuccess(null)
            else -> finishWithError("Failed to scan document (code $resultCode)")
        }
    }

    private fun handleImageResult(resultCode: Int, data: Intent?) {
        when (resultCode) {
            Activity.RESULT_OK -> {
                val pages = GmsDocumentScanningResult.fromActivityResultIntent(data)?.getPages()
                val imageUris = pages
                    ?.mapNotNull { page -> page.getImageUri()?.toString() }
                    ?: emptyList()
                if (imageUris.isNotEmpty()) {
                    finishWithSuccess(
                        mapOf(
                            "images" to imageUris,
                            "count" to imageUris.size,
                            "Uri" to imageUris, // Backward compatible keys
                            "Count" to imageUris.size,
                        )
                    )
                } else {
                    finishWithError("No image results returned")
                }
            }

            Activity.RESULT_CANCELED -> finishWithSuccess(null)
            else -> finishWithError("Failed to scan document (code $resultCode)")
        }
    }

    private fun finishWithSuccess(payload: Any?) {
        pendingResult?.success(payload)
        pendingResult = null
    }

    private fun finishWithError(message: String, throwable: Throwable? = null) {
        pendingResult?.error("SCAN_FAILED", message, throwable?.localizedMessage)
        pendingResult = null
    }

    /**
     * Copies a scanned page from a content URI (produced by ML Kit's Play-services
     * FileProvider) to an on-disk file the caller controls.
     *
     * Args: `uri` (String, the content:// URI) and `destPath` (String, absolute
     * destination path chosen and owned by the caller). Replies `true` on success.
     *
     * The caller owns `destPath`; no path manipulation or validation is performed
     * here beyond opening the streams. On any failure — missing args, null input
     * stream, IO error, or SecurityException (e.g. a URI permission grant that has
     * lapsed) — this fails closed with a static [ERROR_COPY_FAILED] code and a
     * static message. The URI and destination path are never echoed into the error
     * or into logs.
     */
    private fun copyPageToFile(call: MethodCall, result: Result) {
        val uri = call.argument<String>("uri")
        val destPath = call.argument<String>("destPath")
        val context = applicationContext
        if (uri == null || destPath == null || context == null) {
            result.error(ERROR_COPY_FAILED, ERROR_COPY_FAILED_MESSAGE, null)
            return
        }

        try {
            val inputStream = context.contentResolver.openInputStream(Uri.parse(uri))
            if (inputStream == null) {
                result.error(ERROR_COPY_FAILED, ERROR_COPY_FAILED_MESSAGE, null)
                return
            }
            inputStream.use { input ->
                File(destPath).outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            result.success(true)
        } catch (e: IOException) {
            result.error(ERROR_COPY_FAILED, ERROR_COPY_FAILED_MESSAGE, null)
        } catch (e: SecurityException) {
            result.error(ERROR_COPY_FAILED, ERROR_COPY_FAILED_MESSAGE, null)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        activityBinding?.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
        pendingResult = null
    }
}
