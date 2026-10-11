package dev.barcodedeck.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.barcodedeck.app.data.BarcodePattern
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Renders a scanner-readable barcode as pure vector graphics.
 *
 * Sizing rules (mirroring iOS):
 * - Fixed physical size: magnification clamped to GS1 80–200% (≤ 150%),
 *   times an ephemeral pinch-zoom factor.
 * - Bar widths snapped to whole device physical pixels.
 * - Bar height capped at ~60% of the symbol's own width.
 * - Per-type quiet zones reserved inside the layout.
 */
@Composable
fun BarcodeView(
    value: String,
    symbology: String?,
    modifier: Modifier = Modifier,
    zoomScale: Float = 1f,
) {
    val rendered = remember(value, symbology) {
        BarcodePattern.modulesForPresentation(value, symbology)
    }

    if (rendered == null) {
        // Value can't be encoded (e.g. a saved GS1 code with a wrong check
        // digit): show it as large text instead of a blank screen, mirroring
        // the iOS fallback.
        Column(modifier = modifier) {
            Text(
                text = value,
                fontSize = 44.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                color = Color.Black,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(12.dp))
            Text(
                text = "Barcode display unavailable for this type",
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
                color = Color.Black.copy(alpha = 0.5f),
                modifier = Modifier.fillMaxWidth()
            )
        }
        return
    }

    Column(modifier = modifier) {
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
        ) {
            drawBars(rendered.first, rendered.second, zoomScale)
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = value,
            fontSize = 16.sp,
            fontFamily = MaterialTheme.typography.bodyLarge.fontFamily,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            color = Color.Black,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

private fun DrawScope.drawBars(
    modules: List<Boolean>,
    quietModules: Int,
    zoomScale: Float,
) {
    val density = density  // device pixels per dp
    // Nominal Android density: 160 dpi at 1x; points/dp are density-independent.
    val mmPerDp = 25.4f / 160f
    val totalModules = modules.size + 2 * quietModules

    val fitMagnification = size.width.toDouble() * mmPerDp /
        (totalModules * BarcodePattern.NOMINAL_MODULE_WIDTH_MM)
    val magnification = min(1.5, max(0.8, fitMagnification)) * zoomScale.toDouble()

    // Snap the module width to whole device pixels.
    var modulePixels = (BarcodePattern.NOMINAL_MODULE_WIDTH_MM * magnification / mmPerDp * density)
        .roundToInt().coerceAtLeast(2).toFloat()
    while (totalModules * modulePixels > size.width * density && modulePixels > 1) {
        modulePixels -= 1
    }
    val moduleDp = modulePixels / density

    val drawnWidth = totalModules * moduleDp
    val x0 = ((size.width - drawnWidth) / 2f * density).roundToInt() / density

    // Never stretch the code tall: cap the bar height at ~60% of its own width.
    val barHeight = min(size.height, drawnWidth * 0.6f)
    val y0 = (size.height - barHeight) / 2f

    for ((index, isBar) in modules.withIndex()) {
        if (!isBar) continue
        val x = x0 + (quietModules + index) * moduleDp
        drawRect(
            color = Color.Black,
            topLeft = Offset(x, y0),
            size = Size(moduleDp, barHeight)
        )
    }
}
