import Foundation

/// JSON export/import of the card catalog.
///
/// File format (versioned envelope, so old imports keep working when the
/// format evolves):
///
/// ```json
/// {
///   "type": "cardbox-export",
///   "version": 1,
///   "exportedAt": "2026-10-10T12:00:00Z",
///   "cards": [ { "name": …, "description": …, "barcodeValue": …,
///                "symbology": …, "createdAt": … } ]
/// }
/// ```
///
/// Note: the file is plain JSON — readable by anyone who has it. Barcodes
/// themselves aren't secret, but the list reveals personal data.
enum CardTransfer {

    static let typeName = "barcodedeck-export"
    /// Legacy marker written by the pre-rename app; still accepted on import.
    static let legacyTypeName = "cardbox-export"
    static let currentVersion = 1

    // MARK: - Model

    struct Export: Codable {
        var type: String = CardTransfer.typeName
        var version: Int = CardTransfer.currentVersion
        var exportedAt: Date
        var cards: [CardData]
    }

    struct CardData: Codable, Equatable {
        var name: String
        var description: String?
        var barcodeValue: String
        var symbology: String?
        var createdAt: Date
    }

    struct ImportPlan {
        let toImport: [CardData]
        let skipped: Int
    }

    enum TransferError: LocalizedError {
        case notACardboxFile
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notACardboxFile:
                return "This file is not a Barcode Deck export."
            case .unsupportedVersion(let version):
                return "This export uses format version \(version), which is too new for this app."
            }
        }
    }

    // MARK: - Export

    static func makeExport(from cards: [Card]) -> Export {
        Export(
            exportedAt: .now,
            cards: cards.map { card in
                CardData(
                    name: card.name,
                    description: card.cardDescription,
                    barcodeValue: card.barcodeValue,
                    symbology: card.symbology,
                    createdAt: card.createdAt
                )
            }
        )
    }

    static func encode(_ export: Export) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    // MARK: - Import

    static func decodeExport(from data: Data) throws -> Export {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(Export.self, from: data)
        guard export.type == typeName || export.type == legacyTypeName else {
            throw TransferError.notACardboxFile
        }
        guard export.version <= currentVersion else {
            throw TransferError.unsupportedVersion(export.version)
        }
        return export
    }

    /// Plans an import: keeps incoming cards whose barcode value is new,
    /// skips the ones already present (by trimmed barcode value, compared
    /// in canonical EAN-13 form so a 12-digit UPC-A and its 0-padded
    /// EAN-13 twin are the same card). Incoming UPC-A values are stored
    /// padded — see BarcodeValidation.canonicalize.
    static func planImport(_ export: Export, existingValues: Set<String>) -> ImportPlan {
        var seen = Set(existingValues.map { BarcodeValidation.canonicalKey($0) })
        var toImport: [CardData] = []
        var skipped = 0

        for var card in export.cards {
            let value = card.barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || seen.contains(BarcodeValidation.canonicalKey(value)) {
                skipped += 1
                continue
            }
            let (storedValue, storedSymbology) = BarcodeValidation.canonicalize(value, card.symbology)
            card.barcodeValue = storedValue
            card.symbology = storedSymbology
            seen.insert(BarcodeValidation.canonicalKey(storedValue))
            toImport.append(card)
        }

        return ImportPlan(toImport: toImport, skipped: skipped)
    }

    /// Suggested file name for an export, e.g. "BarcodeDeck-2026-10-10.json".
    static func exportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "BarcodeDeck-\(formatter.string(from: .now)).json"
    }

    /// Result of a completed import, for the confirmation dialog.
    struct ImportSummary {
        let imported: Int
        let skipped: Int

        var message: String {
            var parts = ["Imported \(imported) card\(imported == 1 ? "" : "s")."]
            if skipped > 0 {
                parts.append("Skipped \(skipped) already present.")
            }
            return parts.joined(separator: " ")
        }
    }
}
