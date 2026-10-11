package dev.barcodedeck.app.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.view.WindowManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import dev.barcodedeck.app.data.Card
import dev.barcodedeck.app.data.displayBarcodeValue
import dev.barcodedeck.app.data.displayDescription
import dev.barcodedeck.app.data.displayName
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * Full-screen "the phone is the card" mode:
 * - Top half: name + description (single-line, ellipsized).
 * - Bottom half: barcode centered, pinch-zoomable (ephemeral — every entry
 *   starts at the calculated perfect size).
 * - Screen stays awake; brightness is left to the user. An explicit, ephemeral
 *   one-off toggle can force max brightness for the current presentation only
 *   — it is never persisted.
 * - Landscape, system bars hidden.
 * - Tap or swipe (≥ 250 px) exits. Drags on the barcode are consumed by the
 *   zoom gesture, so pinching can never accidentally dismiss.
 * - Orientation restore is automatic: Android rotates natively once the
 *   lock returns to FULL_USER — no transition race like iOS.
 */
@Composable
fun PresentationScreen(card: Card, onDismiss: () -> Unit) {
    val activity = LocalContext.current.findActivity()
    val view = LocalView.current
    var zoomScale by remember { mutableFloatStateOf(1f) }
    /// Ephemeral one-off "force max brightness" intent. Intentionally plain
    /// remember state: it dies when the presentation leaves composition, so
    /// nothing is remembered between presentations.
    var forceMaxBrightness by remember { mutableStateOf(false) }

    DisposableEffect(Unit) {
        val window = activity?.window

        // Keep the screen awake while presenting, but leave brightness to the
        // user: the scanning camera adapts to contrast, and a max-brightness
        // white background acts as a light source shining into the lens, which
        // can degrade reads of long codes. Max brightness remains available as
        // the explicit, ephemeral toggle below.
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window?.let {
            WindowCompat.getInsetsController(it, view).hide(WindowInsetsCompat.Type.systemBars())
        }

        onDispose {
            if (window != null) {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                // Clear any override left by the one-off max-brightness toggle;
                // NONE means "use the user's brightness setting" again.
                val attrs = window.attributes
                attrs.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                window.attributes = attrs
                WindowCompat.getInsetsController(window, view)
                    .show(WindowInsetsCompat.Type.systemBars())
            }
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_USER
        }
    }

    // Applies the one-off brightness override while the toggle is active.
    DisposableEffect(forceMaxBrightness) {
        activity?.window?.let {
            val attrs = it.attributes
            attrs.screenBrightness = if (forceMaxBrightness) {
                WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
            } else {
                WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            }
            it.attributes = attrs
        }
        onDispose { }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .pointerInput(Unit) {
                detectTapGestures { onDismiss() }
            }
            .pointerInput(Unit) {
                var accumulation = Offset.Zero
                detectDragGestures(
                    onDragStart = { accumulation = Offset.Zero },
                    onDragEnd = {
                        if (abs(accumulation.x) > 250f || abs(accumulation.y) > 250f) onDismiss()
                    },
                    onDragCancel = { accumulation = Offset.Zero },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        accumulation += dragAmount
                    }
                )
            }
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Top half: name and description
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .padding(horizontal = 28.dp, vertical = 20.dp)
            ) {
                Text(
                    text = card.displayName,
                    style = MaterialTheme.typography.headlineLarge,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = Color.Black
                )
                card.displayDescription?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = Color.Black.copy(alpha = 0.65f)
                    )
                }
            }

            // Bottom half: barcode centered, pinch-zoomable
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .padding(24.dp),
                contentAlignment = Alignment.Center
            ) {
                BarcodeView(
                    value = card.displayBarcodeValue,
                    symbology = card.symbology,
                    modifier = Modifier
                        .fillMaxSize()
                        .pointerInput(Unit) {
                            detectTransformGestures { _, _, zoom, _ ->
                                zoomScale = (zoomScale * zoom).coerceIn(0.5f, 2.5f)
                            }
                        },
                    zoomScale = zoomScale
                )
            }
        }

        // One-off max-brightness toggle (top end). The IconButton consumes its
        // own taps, so it can never trigger the tap/drag-to-dismiss above.
        // State is ephemeral: leaving the presentation resets it to off.
        IconButton(
            onClick = { forceMaxBrightness = !forceMaxBrightness },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(4.dp)
        ) {
            SunIcon(
                filled = forceMaxBrightness,
                tint = if (forceMaxBrightness) Color.Black else Color.Black.copy(alpha = 0.35f)
            )
        }
    }
}

/**
 * Minimal sun glyph (circle + 8 rays), matching the SF Symbols "sun.max" used
 * on iOS. Drawn with Canvas to avoid pulling in the material-icons-extended
 * dependency for a single glyph.
 */
@Composable
private fun SunIcon(filled: Boolean, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier.size(22.dp)) {
        val center = Offset(size.width / 2f, size.height / 2f)
        val strokeWidth = 1.8.dp.toPx()
        val radius = 4.6.dp.toPx()
        drawCircle(
            color = tint,
            radius = radius,
            center = center,
            style = if (filled) Fill else Stroke(width = strokeWidth, cap = StrokeCap.Round)
        )
        val inner = radius + 1.6.dp.toPx()
        val outer = inner + 2.6.dp.toPx()
        repeat(8) { i ->
            val angle = Math.toRadians((i * 45).toDouble())
            val direction = Offset(cos(angle).toFloat(), sin(angle).toFloat())
            drawLine(
                color = tint,
                start = center + direction * inner,
                end = center + direction * outer,
                strokeWidth = strokeWidth,
                cap = StrokeCap.Round
            )
        }
    }
}

private fun Context.findActivity(): Activity? {
    var context = this
    while (context is ContextWrapper) {
        if (context is Activity) return context
        context = context.baseContext
    }
    return null
}
