import Vision

/// Barcode value validation (GS1 check digits), symbology classification,
/// and the 1D symbology set used for scanning.
enum BarcodeValidation {

    /// All linear (1D) symbologies we scan for. QR and other 2D codes are
    /// intentionally excluded for v1.
    static let scanSymbologies: [VNBarcodeSymbology] = [
        .ean13, .ean8, .upce,
        .code39, .code39FullASCII, .code93, .code93i, .code128,
        .i2of5, .i2of5Checksum, .itf14,
        .codabar, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited,
        .msiPlessey,
        // Stacked linear codes, common on membership/ID cards.
        .pdf417, .microPDF417,
    ]

    /// Human-readable name for a scanned symbology, or `nil` when unknown
    /// (the row simply shows no badge).
    static func name(for symbology: VNBarcodeSymbology) -> String? {
        switch symbology {
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upce: return "UPC-E"
        case .code39: return "Code 39"
        case .code39FullASCII: return "Code 39"
        case .code93, .code93i: return "Code 93"
        case .code128: return "Code 128"
        case .i2of5, .i2of5Checksum: return "ITF"
        case .itf14: return "ITF-14"
        case .codabar: return "Codabar"
        case .gs1DataBar: return "GS1 DataBar"
        case .gs1DataBarExpanded: return "GS1 DataBar Exp."
        case .gs1DataBarLimited: return "GS1 DataBar Ltd."
        case .msiPlessey: return "MSI"
        case .pdf417, .microPDF417: return "PDF417"
        default: return nil
        }
    }

    // MARK: - Check digits

    /// Computes the GS1 check digit for a numeric payload (the value without
    /// its final digit: 12 for EAN-13, 11 for UPC-A, 7 for EAN-8).
    static func gs1CheckDigit(_ payload: String) -> Int? {
        guard let digits = asciiDigits(payload), digits.count == payload.count else {
            return nil
        }
        var sum = 0
        var weight = 3
        for digit in digits.reversed() {
            sum += digit * weight
            weight = (weight == 3) ? 1 : 3
        }
        return (10 - sum % 10) % 10
    }

    /// Validates the final (check) digit of a GS1-style numeric code
    /// (EAN-8, UPC-A, EAN-13). Weights alternate 3/1 from the right.
    static func hasValidGS1CheckDigit(_ value: String) -> Bool {
        guard let digits = asciiDigits(value), digits.count == value.count else {
            return false
        }
        guard let expected = digits.last else { return false }
        var sum = 0
        var weight = 3
        for digit in digits.dropLast().reversed() {
            sum += digit * weight
            weight = (weight == 3) ? 1 : 3
        }
        return (10 - sum % 10) % 10 == expected
    }

    static func isValidEAN13(_ value: String) -> Bool {
        value.count == 13 && hasValidGS1CheckDigit(value)
    }

    static func isValidUPCA(_ value: String) -> Bool {
        value.count == 12 && hasValidGS1CheckDigit(value)
    }

    static func isValidEAN8(_ value: String) -> Bool {
        value.count == 8 && hasValidGS1CheckDigit(value)
    }

    /// Classifies an ASCII-digit value into a symbology name when its length
    /// and check digit match a known GS1 format; otherwise `nil`.
    /// Used for manually typed values (scanned values carry their own
    /// symbology from the camera).
    static func classify(_ value: String) -> String? {
        guard let digits = asciiDigits(value), digits.count == value.count else {
            return nil
        }
        switch digits.count {
        case 13 where hasValidGS1CheckDigit(value): return "EAN-13"
        case 12 where hasValidGS1CheckDigit(value): return "UPC-A"
        case 8 where hasValidGS1CheckDigit(value): return "EAN-8"
        default: return nil
        }
    }

    // MARK: - Manual entry

    /// Types offered for manual entry, alphabetically, with Auto-detect
    /// (`nil`) first. Only symbologies the app can render in presentation
    /// mode are offered — scanned cards may carry any scanned type.
    static let manualTypeOptions: [String?] = [
        nil, "Code 128", "Code 39", "EAN-13", "UPC-A",
    ]

    /// Resolves the Auto-detect selection into the symbology to store: a
    /// valid GS1 classification when the digits match one, otherwise Code 128
    /// (the universal, renderable fallback) — or `nil` when the value cannot
    /// be encoded at all (presentation will show it as plain text).
    static func resolveAutoSymbology(_ value: String) -> String? {
        if let classified = classify(value) { return classified }
        return isCode128Encodable(value) ? "Code 128" : nil
    }

    /// Whether every character is ASCII 32–126, i.e. Code 128 Code Set B.
    static func isCode128Encodable(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { (32...126).contains($0.value) }
    }

    /// Characters of `value` that Code 39 cannot encode (case-insensitive),
    /// deduplicated in order of first appearance.
    static func invalidCode39Characters(_ value: String) -> [Character] {
        var seen = Set<Character>()
        var invalid: [Character] = []
        for character in value.uppercased() where !BarcodePattern.code39AllowedCharacters.contains(character) {
            if seen.insert(character).inserted {
                invalid.append(character)
            }
        }
        return invalid
    }

    /// Hard validation for a manually chosen type: an error message when the
    /// value can never be encoded as that type, `nil` when OK. A GS1 value
    /// with a wrong check digit is also a hard error: it could neither be
    /// rendered nor scanned, so saving it would only create a dead card.
    static func manualTypeError(type: String?, value: String) -> String? {
        guard let type else { return nil }  // Auto-detect never hard-fails
        switch type {
        case "EAN-13":
            guard asciiDigits(value) != nil else { return "EAN-13 uses digits only." }
            guard value.count == 13 else {
                return "EAN-13 needs exactly 13 digits (currently \(value.count))."
            }
            guard hasValidGS1CheckDigit(value) else {
                return "Check digit doesn't match — expected \(gs1CheckDigit(String(value.prefix(12))) ?? 0). "
                    + "Double-check the digits before saving."
            }
        case "UPC-A":
            guard asciiDigits(value) != nil else { return "UPC-A uses digits only." }
            guard value.count == 12 else {
                return "UPC-A needs exactly 12 digits (currently \(value.count))."
            }
            guard hasValidGS1CheckDigit(value) else {
                return "Check digit doesn't match — expected \(gs1CheckDigit(String(value.prefix(11))) ?? 0). "
                    + "Double-check the digits before saving."
            }
        case "Code 39":
            let invalid = invalidCode39Characters(value)
            guard invalid.isEmpty else {
                let quoted = invalid.map(String.init).joined(separator: ", ")
                return "Code 39 can't encode: \(quoted)."
            }
        case "Code 128":
            guard isCode128Encodable(value) else {
                return "Code 128 needs plain ASCII characters."
            }
        default:
            return nil
        }
        return nil
    }

    private static func asciiDigits(_ value: String) -> [Int]? {
        var digits: [Int] = []
        digits.reserveCapacity(value.count)
        for character in value {
            guard character.isASCII, let digit = character.wholeNumberValue, digit >= 0 else {
                return nil
            }
            digits.append(digit)
        }
        return digits
    }
}
