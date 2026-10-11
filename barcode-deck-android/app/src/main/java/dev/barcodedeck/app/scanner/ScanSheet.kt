package dev.barcodedeck.app.scanner

import android.Manifest
import android.view.HapticFeedbackConstants
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * Full-screen camera scanner. On a locked barcode fires [onCapture]
 * (after a success haptic); "Type it in" fires [onManualEntry]. Both close
 * the scanner — the caller then presents the add form.
 */
@Composable
fun ScanSheet(
    onCapture: (value: String, symbology: String?) -> Unit,
    onManualEntry: () -> Unit,
    onCancel: () -> Unit,
) {
    val view = LocalView.current
    var cameraUnavailable by remember { mutableStateOf(false) }
    var hasPermission by rememberSaveable { mutableStateOf(false) }
    var permissionDenied by rememberSaveable { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasPermission = granted
        if (!granted) permissionDenied = true
    }

    LaunchedEffect(Unit) {
        permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        if (hasPermission && !cameraUnavailable) {
            ScannerCameraView(
                onDetected = { value, symbology ->
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    onCapture(value, symbology)
                },
                onUnavailable = { cameraUnavailable = true }
            )
            Overlay(
                onManualEntry = onManualEntry,
                onCancel = onCancel
            )
        } else {
            Fallback(
                cameraUnavailable = cameraUnavailable,
                permissionDenied = permissionDenied,
                onManualEntry = onManualEntry,
                onCancel = onCancel
            )
        }
    }
}

@Composable
private fun Overlay(onManualEntry: () -> Unit, onCancel: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            "Scan barcode",
            style = MaterialTheme.typography.titleMedium,
            color = Color.White
        )
        androidx.compose.foundation.Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp)
        ) {
            drawRoundRect(
                color = Color.White.copy(alpha = 0.9f),
                style = androidx.compose.ui.graphics.drawscope.Stroke(
                    width = 4f,
                    pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(20f, 14f))
                ),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(32f, 32f)
            )
        }
        Text(
            "Align the barcode inside the frame",
            style = MaterialTheme.typography.bodyMedium,
            color = Color.White.copy(alpha = 0.8f)
        )
        Row(modifier = Modifier.fillMaxWidth()) {
            TextButton(onClick = onManualEntry) {
                Text("Type it in", color = Color.White)
            }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onCancel) {
                Text("Cancel", color = Color.White)
            }
        }
    }
}

@Composable
private fun Fallback(
    cameraUnavailable: Boolean,
    permissionDenied: Boolean,
    onManualEntry: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Filled.Warning,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.6f),
            modifier = Modifier.height(56.dp)
        )
        Spacer(Modifier.height(16.dp))
        Text(
            "Camera unavailable",
            style = MaterialTheme.typography.titleLarge,
            color = Color.White
        )
        Spacer(Modifier.height(8.dp))
        Text(
            when {
                permissionDenied -> "Camera permission was denied — you can type the barcode instead."
                cameraUnavailable -> "Scanning needs a camera — on devices without one you can type the barcode instead."
                else -> "Scanning is starting…"
            },
            style = MaterialTheme.typography.bodyMedium,
            color = Color.White.copy(alpha = 0.7f),
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(32.dp))
        Button(onClick = onManualEntry, modifier = Modifier.fillMaxWidth()) {
            Text("Type it in")
        }
        TextButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) {
            Text("Cancel")
        }
    }
}
