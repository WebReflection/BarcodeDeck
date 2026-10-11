package dev.barcodedeck.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.barcodedeck.app.data.Card
import dev.barcodedeck.app.data.CardTransfer
import dev.barcodedeck.app.scanner.ScanSheet
import dev.barcodedeck.app.ui.AddCardSheet
import dev.barcodedeck.app.ui.CardListScreen
import dev.barcodedeck.app.ui.PresentationScreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What the add form should be prefilled with. */
sealed interface AddCardContext {
    data class Scanned(val value: String, val symbology: String?) : AddCardContext
    data object Manual : AddCardContext
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            dev.barcodedeck.app.ui.BarcodeDeckTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    CardDeckApp()
                }
            }
        }
    }
}

@Composable
private fun CardDeckApp(viewModel: CardViewModel = viewModel()) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()

    val cards by viewModel.cards.collectAsStateWithLifecycle()
    val existingBarcodeNames by viewModel.existingBarcodeNames.collectAsStateWithLifecycle()

    var showScanner by rememberSaveable { mutableStateOf(false) }
    var addContext by remember { mutableStateOf<AddCardContext?>(null) }
    var presentedCard by remember { mutableStateOf<Card?>(null) }

    var importSummary by remember { mutableStateOf<String?>(null) }
    var dialogError by remember { mutableStateOf<String?>(null) }
    var pendingExportJson by remember { mutableStateOf<String?>(null) }

    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        val json = pendingExportJson
        if (uri != null && json != null) {
            scope.launch {
                try {
                    withContext(Dispatchers.IO) {
                        context.contentResolver.openOutputStream(uri)?.use { stream ->
                            stream.write(json.toByteArray())
                        } ?: throw IllegalStateException("Could not open the destination file.")
                    }
                } catch (e: Exception) {
                    dialogError = "Export failed: ${e.message}"
                }
            }
        }
        pendingExportJson = null
    }

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            scope.launch {
                try {
                    val data = withContext(Dispatchers.IO) {
                        context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    } ?: throw IllegalStateException("Could not read the selected file.")

                    val export = CardTransfer.decode(String(data))
                    val plan = CardTransfer.planImport(
                        export,
                        existingValues = viewModel.existingBarcodeNames.value.keys
                    )
                    viewModel.importCards(plan.toImport.map {
                        Card(
                            // Imported values are trimmed like manually typed
                            // ones; no supported symbology here carries
                            // meaningful leading/trailing whitespace.
                            name = it.name.trim(),
                            description = it.description?.trim()?.ifEmpty { null },
                            barcodeValue = it.barcodeValue.trim(),
                            symbology = it.symbology?.trim()?.ifEmpty { null },
                            createdAt = it.createdAt
                        )
                    })
                    importSummary =
                        "Imported ${plan.toImport.size} card" +
                            if (plan.toImport.size == 1) "" else "s" +
                            if (plan.skipped > 0) ". Skipped ${plan.skipped} already present." else "."
                } catch (e: Exception) {
                    dialogError = e.message ?: "Import failed."
                }
            }
        }
    }

    CardListScreen(
        cards = cards,
        exportEnabled = cards.isNotEmpty(),
        onAddClick = { showScanner = true },
        onCardClick = { presentedCard = it },
        onDelete = { viewModel.delete(it) },
        onRestore = { viewModel.restore(it) },
        onReorder = { viewModel.reorder(it) },
        onExport = {
            pendingExportJson = CardTransfer.export(viewModel.cards.value)
            exportLauncher.launch(CardTransfer.exportFileName())
        },
        onImport = { importLauncher.launch(arrayOf("application/json")) }
    ) {
        FloatingActionButton(onClick = { showScanner = true }) {
            Icon(Icons.Filled.Add, contentDescription = "Add card")
        }
    }

    presentedCard?.let { card ->
        PresentationScreen(card = card, onDismiss = { presentedCard = null })
    }

    if (showScanner) {
        ScanSheet(
            onCapture = { value, symbology ->
                showScanner = false
                addContext = AddCardContext.Scanned(value, symbology)
            },
            onManualEntry = {
                showScanner = false
                addContext = AddCardContext.Manual
            },
            onCancel = { showScanner = false }
        )
    }

    val currentAddContext = addContext
    if (currentAddContext != null) {
        val (prefilledValue, prefilledSymbology) = when (val ctx = currentAddContext) {
            is AddCardContext.Scanned -> ctx.value to ctx.symbology
            is AddCardContext.Manual -> "" to null
            else -> return
        }
        AddCardSheet(
            prefilledValue = prefilledValue,
            prefilledSymbology = prefilledSymbology,
            existingBarcodeNames = existingBarcodeNames,
            onDismiss = { addContext = null },
            onSave = { name, description, barcodeValue, symbology ->
                viewModel.add(name, description, barcodeValue, symbology)
                addContext = null
            }
        )
    }

    importSummary?.let { summary ->
        AlertDialog(
            onDismissRequest = { importSummary = null },
            confirmButton = { TextButton(onClick = { importSummary = null }) { Text("OK") } },
            title = { Text("Import complete") },
            text = { Text(summary) }
        )
    }

    dialogError?.let { error ->
        AlertDialog(
            onDismissRequest = { dialogError = null },
            confirmButton = { TextButton(onClick = { dialogError = null }) { Text("OK") } },
            title = { Text("Something went wrong") },
            text = { Text(error) }
        )
    }
}
