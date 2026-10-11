package dev.barcodedeck.app.scanner

import android.content.pm.PackageManager
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.launch
import androidx.lifecycle.compose.LocalLifecycleOwner

/** All linear (1D) symbologies we scan for — QR and other 2D codes excluded,
 *  except stacked PDF417 (common on membership/ID cards). */
private val scanFormats = intArrayOf(
    Barcode.FORMAT_EAN_13, Barcode.FORMAT_EAN_8, Barcode.FORMAT_UPC_A, Barcode.FORMAT_UPC_E,
    Barcode.FORMAT_CODE_128, Barcode.FORMAT_CODE_39, Barcode.FORMAT_CODE_93,
    Barcode.FORMAT_ITF, Barcode.FORMAT_CODABAR, Barcode.FORMAT_PDF417,
)

fun symbologyName(format: Int): String? = when (format) {
    Barcode.FORMAT_EAN_13 -> "EAN-13"
    Barcode.FORMAT_EAN_8 -> "EAN-8"
    Barcode.FORMAT_UPC_A -> "UPC-A"
    Barcode.FORMAT_UPC_E -> "UPC-E"
    Barcode.FORMAT_CODE_39 -> "Code 39"
    Barcode.FORMAT_CODE_93 -> "Code 93"
    Barcode.FORMAT_CODE_128 -> "Code 128"
    Barcode.FORMAT_ITF -> "ITF"
    Barcode.FORMAT_CODABAR -> "Codabar"
    Barcode.FORMAT_PDF417 -> "PDF417"
    else -> null
}

/**
 * CameraX + ML Kit barcode scanner. Fires [onDetected] once on the first
 * locked barcode, or [onUnavailable] when scanning cannot start
 * (no camera — e.g. emulator — or permission denied).
 */
@Composable
fun ScannerCameraView(
    onDetected: (value: String, symbology: String?) -> Unit,
    onUnavailable: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val previewView = remember {
        PreviewView(context).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }
    }
    var provider by remember { mutableStateOf<ProcessCameraProvider?>(null) }
    val latestOnDetected by rememberUpdatedState(onDetected)
    val latestOnUnavailable by rememberUpdatedState(onUnavailable)

    AndroidView(factory = { previewView }, modifier = Modifier.fillMaxSize())

    DisposableEffect(Unit) {
        onDispose { provider?.unbindAll() }
    }

    androidx.compose.runtime.LaunchedEffect(Unit) {
        val hasCamera = context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
        if (!hasCamera) {
            latestOnUnavailable()
            return@LaunchedEffect
        }

        try {
            val cameraProvider = ProcessCameraProvider.getInstance(context).await()
            provider = cameraProvider

            val options = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(scanFormats[0], *scanFormats.copyOfRange(1, scanFormats.size))
                .build()
            val scanner = BarcodeScanning.getClient(options)
            val executor = Executors.newSingleThreadExecutor()
            var captured = false

            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
            analysis.setAnalyzer(executor) { proxy ->
                if (captured) {
                    proxy.close()
                    return@setAnalyzer
                }
                val mediaImage = proxy.image
                if (mediaImage == null) {
                    proxy.close()
                    return@setAnalyzer
                }
                val input = InputImage.fromMediaImage(mediaImage, proxy.imageInfo.rotationDegrees)
                scanner.process(input)
                    .addOnSuccessListener { barcodes ->
                        val barcode = barcodes.firstOrNull { !it.rawValue.isNullOrEmpty() } ?: return@addOnSuccessListener
                        captured = true
                        val value = barcode.rawValue!!
                        val symbology = symbologyName(barcode.format)
                        ContextCompat.getMainExecutor(context).execute {
                            latestOnDetected(value, symbology)
                        }
                    }
                    .addOnCompleteListener { proxy.close() }
            }

            cameraProvider.unbindAll()
            cameraProvider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) },
                analysis
            )
        } catch (e: Exception) {
            latestOnUnavailable()
        }
    }
}
