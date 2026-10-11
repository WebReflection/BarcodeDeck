import Foundation
import SwiftData

/// A saved barcoded card: a mandatory name, an optional description,
/// and the barcode value (with its symbology when known).
@Model
final class Card {
    /// Display name of the card (e.g. "Green Grocery"). Mandatory.
    var name: String

    /// Optional free-form description.
    var cardDescription: String?

    /// The recognized barcode value (digits/characters as encoded).
    var barcodeValue: String

    /// The barcode symbology detected during scanning, when known
    /// (e.g. "EAN-13", "UPC-A", "Code-128"). `nil` for manual entry
    /// until the value is classified.
    var symbology: String?

    /// Creation date; used for sorting the list (newest first).
    var createdAt: Date

    init(
        name: String,
        cardDescription: String? = nil,
        barcodeValue: String,
        symbology: String? = nil,
        createdAt: Date = .now
    ) {
        self.name = name
        self.cardDescription = cardDescription
        self.barcodeValue = barcodeValue
        self.symbology = symbology
        self.createdAt = createdAt
    }
}

extension Card {
    /// The name with surrounding whitespace removed — what we always display.
    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The description with surrounding whitespace removed, or `nil` when empty.
    var displayDescription: String? {
        guard let text = cardDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    /// The barcode value with surrounding whitespace removed.
    var displayBarcodeValue: String {
        barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
