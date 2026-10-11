package dev.barcodedeck.app.ui

import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri

/**
 * The "About" dialog: essential info only, reached from the overflow menu
 * so it never disturbs the main flow. Points to the project's repository
 * for contributions, feedback and appreciation — no contact e-mail.
 */
object About {
    const val PROJECT_URL = "https://github.com/WebReflection/BarcodeDeck"
    const val ISSUES_URL = "$PROJECT_URL/issues"
    const val LICENSE_NAME = "MIT License"
}

private fun openUrl(context: android.content.Context, url: String) {
    context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()))
}

@Composable
fun AboutDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val versionName = remember {
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull()
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (versionName.isNullOrBlank()) "Barcode Deck" else "Barcode Deck $versionName") },
        text = {
            Column {
                Text(
                    "One card less in your wallet. Free, open source and " +
                        "offline — your cards never leave this device, and " +
                        "there is no account, analytics or tracking."
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    "The camera is used only to look at barcodes.",
                    style = MaterialTheme.typography.bodySmall
                )
                Spacer(Modifier.height(8.dp))
                TextButton(onClick = { openUrl(context, About.PROJECT_URL) }) {
                    Text("Source code & contributions")
                }
                TextButton(onClick = { openUrl(context, About.ISSUES_URL) }) {
                    Text("Feedback & issues")
                }
                Text(
                    "Released under the ${About.LICENSE_NAME}.",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        }
    )
}
