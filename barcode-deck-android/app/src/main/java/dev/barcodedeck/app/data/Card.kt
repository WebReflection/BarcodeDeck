package dev.barcodedeck.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * A saved barcoded card: a mandatory name, an optional description,
 * and the barcode value (with its symbology when known).
 * Mirrors the iOS model; the JSON transfer format uses the same field names.
 */
@Entity(tableName = "cards")
data class Card(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val description: String? = null,
    val barcodeValue: String,
    val symbology: String? = null,
    val createdAt: Long = System.currentTimeMillis()
)

val Card.displayName: String
    get() = name.trim()

val Card.displayDescription: String?
    get() = description?.trim()?.takeIf { it.isNotEmpty() }

val Card.displayBarcodeValue: String
    get() = barcodeValue.trim()
