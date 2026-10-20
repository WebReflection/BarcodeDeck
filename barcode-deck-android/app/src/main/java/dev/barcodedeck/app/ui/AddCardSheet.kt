package dev.barcodedeck.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import dev.barcodedeck.app.data.BarcodeValidation

/**
 * Form for adding a new card. Presented either blank (manual entry) or
 * prefilled with a scanned barcode value + symbology from the camera.
 *
 * The type dropdown (before the value field) constrains and validates manual
 * entry; Auto-detect resolves to a valid GS1 classification or Code 128.
 *
 * [existingBarcodeNames] maps barcode value → card name, for the duplicate warning.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddCardSheet(
    prefilledValue: String = "",
    prefilledSymbology: String? = null,
    existingBarcodeNames: Map<String, String>,
    onDismiss: () -> Unit,
    onSave: (name: String, description: String?, barcodeValue: String, symbology: String?) -> Unit
) {
    var name by rememberSaveable { mutableStateOf("") }
    var description by rememberSaveable { mutableStateOf("") }
    var barcodeValue by rememberSaveable { mutableStateOf(prefilledValue) }
    // The manually chosen type (null = Auto-detect). Initialized to the
    // scanned symbology when it is one of the selectable options.
    var selectedType by rememberSaveable {
        mutableStateOf(
            if (BarcodeValidation.manualTypeOptions.contains(prefilledSymbology)) prefilledSymbology
            else null
        )
    }
    var typeExpanded by remember { mutableStateOf(false) }

    val trimmedName = name.trim()
    val trimmedDescription = description.trim().takeIf { it.isNotEmpty() }
    val trimmedBarcodeValue = barcodeValue.trim()
    val typeError = BarcodeValidation.manualTypeError(selectedType, trimmedBarcodeValue)
    val canSave = trimmedName.isNotEmpty() && trimmedBarcodeValue.isNotEmpty() && typeError == null

    fun onValueChange(newValue: String) {
        // Code 39 has no lowercase: bring input along as it is typed.
        barcodeValue = if (selectedType == "Code 39") newValue.uppercase() else newValue
    }

    // The symbology to persist:
    // - the scanned one while the value is untouched and the type is Auto,
    // - the explicitly chosen type,
    // - otherwise the Auto-detect resolution of the typed value.
    val effectiveSymbology: String? =
        if (prefilledSymbology != null && trimmedBarcodeValue == prefilledValue && selectedType == null) {
            prefilledSymbology
        } else if (selectedType != null) {
            selectedType
        } else {
            BarcodeValidation.resolveAutoSymbology(trimmedBarcodeValue)
        }

    val duplicateName = existingBarcodeNames[trimmedBarcodeValue]

    // (text, isError) pairs, rendered in order.
    val footerMessages: List<Pair<String, Boolean>> = buildList {
        if (typeError != null) {
            add(typeError to true)
        } else if (trimmedBarcodeValue.isNotEmpty()) {
            if (prefilledSymbology != null && trimmedBarcodeValue == prefilledValue) {
                add("Scanned as $prefilledSymbology." to false)
            } else if (selectedType != null) {
                when {
                    selectedType == "EAN-13" && trimmedBarcodeValue.length < 13 ->
                        add("${trimmedBarcodeValue.length}/13 digits" to false)
                    selectedType == "UPC-A" && trimmedBarcodeValue.length < 12 ->
                        add("${trimmedBarcodeValue.length}/12 digits" to false)
                    (selectedType == "EAN-13" && trimmedBarcodeValue.length == 13) ||
                        (selectedType == "UPC-A" && trimmedBarcodeValue.length == 12) ->
                        add("Valid $selectedType check digit." to false)
                    selectedType == "Code 39" ->
                        add("Uppercase letters, digits, space and - . \$ / + %." to false)
                    selectedType == "Code 128" ->
                        add("Letters, digits and symbols (plain ASCII)." to false)
                    selectedType == "ITF" ->
                        add(
                            "Digits in pairs; a 14-digit code (ITF-14) gets its " +
                                "check digit validated." to false
                        )
                    selectedType == "QR Code" ->
                        add("Any text — encoded exactly as typed." to false)
                }
            } else {
                // Auto-detect: explain what the value resolves to.
                val classified = BarcodeValidation.classify(trimmedBarcodeValue)
                val allAsciiDigits = trimmedBarcodeValue.all { it in '0'..'9' }
                when {
                    classified != null ->
                        add("Auto-detected: $classified (valid check digit)." to false)
                    allAsciiDigits && trimmedBarcodeValue.length in setOf(8, 12, 13, 14) ->
                        add(
                            "Check digit doesn't match — double-check the digits. "
                                + "Auto will save it as Code 128." to true
                        )
                    BarcodeValidation.isCode128Encodable(trimmedBarcodeValue) ->
                        add("Auto will save it as Code 128." to false)
                    else ->
                        add(
                            "Can't be encoded as a barcode — presentation will show it as text."
                                to true
                        )
                }
            }
        }
        if (duplicateName != null) {
            add("Already saved as “$duplicateName”. You can still save it." to true)
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        // Scrollable so the user can bring any field above the keyboard
        // manually while typing.
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
        ) {
            Text("New Card", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(12.dp))

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = description,
                onValueChange = { description = it },
                label = { Text("Description (optional)") },
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
            ExposedDropdownMenuBox(
                expanded = typeExpanded,
                onExpandedChange = { typeExpanded = it }
            ) {
                OutlinedTextField(
                    value = selectedType ?: "Auto-detect",
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Type") },
                    trailingIcon = {
                        ExposedDropdownMenuDefaults.TrailingIcon(expanded = typeExpanded)
                    },
                    modifier = Modifier
                        .menuAnchor()
                        .fillMaxWidth()
                )
                ExposedDropdownMenu(
                    expanded = typeExpanded,
                    onDismissRequest = { typeExpanded = false }
                ) {
                    BarcodeValidation.manualTypeOptions.forEach { type ->
                        DropdownMenuItem(
                            text = { Text(type ?: "Auto-detect") },
                            onClick = {
                                // Code 39 has no lowercase: bring existing input along.
                                if (type == "Code 39") {
                                    barcodeValue = barcodeValue.uppercase()
                                }
                                selectedType = type
                                typeExpanded = false
                            }
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = barcodeValue,
                onValueChange = ::onValueChange,
                label = { Text("Barcode value") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = when (selectedType) {
                        "EAN-13", "UPC-A", "ITF" -> KeyboardType.Number
                        else -> KeyboardType.Ascii
                    },
                    capitalization = if (selectedType == "Code 39") {
                        KeyboardCapitalization.Characters
                    } else {
                        KeyboardCapitalization.None
                    }
                ),
                textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(4.dp))
            for ((message, isError) in footerMessages) {
                Text(
                    message,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (isError) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(Modifier.height(16.dp))

            Row {
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Button(
                    onClick = { onSave(trimmedName, trimmedDescription, trimmedBarcodeValue, effectiveSymbology) },
                    enabled = canSave
                ) {
                    Text("Save")
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}
