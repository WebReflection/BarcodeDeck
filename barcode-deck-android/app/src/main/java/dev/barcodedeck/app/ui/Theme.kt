package dev.barcodedeck.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * Barcode Deck theme: stark ink-on-paper monochrome, matching the outlined
 * two-cards icon. Light = black ink on paper white; Dark = white ink on ink.
 */
private val Ink = Color(0xFF0A0A0A)
private val Paper = Color(0xFFFAFAFA)
private val InkSoft = Color(0xFF5F5F5F)
private val PaperSoft = Color(0xFFAAAAAA)

private val LightColors = lightColorScheme(
    primary = Ink,
    onPrimary = Paper,
    primaryContainer = Ink,
    onPrimaryContainer = Paper,
    background = Paper,
    onBackground = Ink,
    surface = Paper,
    onSurface = Ink,
    surfaceVariant = Color(0xFFEDEDED),
    onSurfaceVariant = InkSoft,
    error = Color(0xFFB3261E),
    onError = Paper
)

private val DarkColors = darkColorScheme(
    primary = Paper,
    onPrimary = Ink,
    primaryContainer = Paper,
    onPrimaryContainer = Ink,
    background = Color(0xFF0A0A0A),
    onBackground = Paper,
    surface = Color(0xFF141414),
    onSurface = Paper,
    surfaceVariant = Color(0xFF232323),
    onSurfaceVariant = PaperSoft,
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF0A0A0A)
)

@Composable
fun BarcodeDeckTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    MaterialTheme(
        colorScheme = if (dark) DarkColors else LightColors,
        content = content
    )
}
