package dev.barcodedeck.app.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset

/**
 * JSON export/import of the card catalog.
 *
 * Same file format as the iOS app (versioned envelope, ISO-8601 dates),
 * so decks are cross-platform and forward-compatible:
 *
 * ```json
 * {
 *   "type": "barcodedeck-export",
 *   "version": 1,
 *   "exportedAt": "2026-10-10T12:00:00Z",
 *   "cards": [ { "name": …, "description": …, "barcodeValue": …,
 *                "symbology": …, "createdAt": … } ]
 * }
 * ```
 *
 * The file is plain JSON — readable by anyone who has it. Barcodes
 * themselves aren't secret, but the list reveals personal data.
 */

/** Long (epoch millis) serialized as an ISO-8601 timestamp string. */
object Iso8601Serializer : kotlinx.serialization.KSerializer<Long> {
    override val descriptor = kotlinx.serialization.descriptors.PrimitiveSerialDescriptor(
        "ISO8601Timestamp",
        kotlinx.serialization.descriptors.PrimitiveKind.STRING
    )

    override fun serialize(encoder: kotlinx.serialization.encoding.Encoder, value: Long) {
        encoder.encodeString(Instant.ofEpochMilli(value).atOffset(ZoneOffset.UTC).toString())
    }

    override fun deserialize(decoder: kotlinx.serialization.encoding.Decoder): Long =
        OffsetDateTime.parse(decoder.decodeString()).toInstant().toEpochMilli()
}

@Serializable
data class CardData(
    val name: String,
    val description: String? = null,
    val barcodeValue: String,
    val symbology: String? = null,
    @Serializable(with = Iso8601Serializer::class) val createdAt: Long
)

@Serializable
data class CardExport(
    val type: String,
    val version: Int,
    @Serializable(with = Iso8601Serializer::class) val exportedAt: Long,
    val cards: List<CardData>
)

data class ImportPlan(
    val toImport: List<CardData>,
    val skipped: Int
)

class TransferException(message: String) : Exception(message)

object CardTransfer {

    const val TYPE = "barcodedeck-export"

    /** Legacy marker written by the pre-rename iOS app; still accepted on import. */
    const val LEGACY_TYPE = "cardbox-export"
    const val VERSION = 1

    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = true
    }

    fun export(cards: List<Card>): String {
        val export = CardExport(
            type = TYPE,
            version = VERSION,
            exportedAt = System.currentTimeMillis(),
            cards = cards.map {
                CardData(
                    name = it.name,
                    description = it.description,
                    barcodeValue = it.barcodeValue,
                    symbology = it.symbology,
                    createdAt = it.createdAt
                )
            }
        )
        return json.encodeToString(export)
    }

    fun decode(data: String): CardExport {
        val export = try {
            json.decodeFromString(CardExport.serializer(), data)
        } catch (e: Exception) {
            throw TransferException("This file is not a Barcode Deck export.")
        }
        if (export.type != TYPE && export.type != LEGACY_TYPE) {
            throw TransferException("This file is not a Barcode Deck export.")
        }
        if (export.version > VERSION) {
            throw TransferException("This export uses format version ${export.version}, which is too new for this app.")
        }
        return export
    }

    /** Plans an import: keeps incoming cards whose barcode value is new,
     *  skips the ones already present (by trimmed barcode value). */
    fun planImport(export: CardExport, existingValues: Set<String>): ImportPlan {
        val seen = existingValues.toMutableSet()
        val toImport = mutableListOf<CardData>()
        var skipped = 0

        for (card in export.cards) {
            val value = card.barcodeValue.trim()
            if (value.isEmpty() || seen.contains(value)) {
                skipped++
                continue
            }
            seen += value
            toImport += card
        }
        return ImportPlan(toImport, skipped)
    }

    /** Suggested file name for an export, e.g. "BarcodeDeck-2026-10-10.json". */
    fun exportFileName(): String {
        val formatter = java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd")
        return "BarcodeDeck-${java.time.LocalDate.now().format(formatter)}.json"
    }
}
