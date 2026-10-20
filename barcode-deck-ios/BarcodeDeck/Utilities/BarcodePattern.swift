import CoreImage
import Foundation

/// A value resolved into something presentation mode can draw.
enum PresentationBarcode {
    /// 1D symbol: module runs, quiet zone, nominal module width (mm).
    case linear(modules: [Bool], quietModules: Int, nominalModuleWidthMM: Double)

    /// 2D symbol: QR code image plus its module count (the generator emits
    /// one pixel per module, no quiet zone).
    case qr(image: CGImage, moduleCount: Int)
}

/// Encodes barcode values into module patterns (`true` = bar, `false` = space).
/// Kotlin port of the Android BarcodePattern — same tables, same test vectors.
///
/// Renders EAN-13, EAN-8, UPC-A (encoded as EAN-13 with a leading 0), Code 128
/// (Code Set B), Code 39, ITF (incl. ITF-14) and QR codes.
enum BarcodePattern {

    /// Number of modules in a complete EAN-13 symbol.
    static let ean13ModuleCount = 95

    /// Nominal module width at 100% magnification, in millimetres (GS1).
    static let nominalModuleWidthMM = 0.33

    /// ITF-14's GS1 minimum X-dimension is 0.495 mm, so ITF renders with a
    /// larger nominal module than 1D retail codes.
    static let itfNominalModuleWidthMM = 0.495

    /// Reserved quiet zones for EAN-13, in modules (GS1: ≥ 11 left, ≥ 7 right).
    static let ean13QuietModules = 11
    static let ean8QuietModules = 7
    static let code128QuietModules = 10
    static let code39QuietModules = 10
    static let itfQuietModules = 10

    /// QR quiet zone (spec recommendation: 4 modules).
    static let qrQuietModules = 4

    /// Shared CoreImage context for QR generation (created lazily, once).
    private static let ciContext = CIContext()

    /// Resolves a card into a drawable pattern, or `nil` when the value cannot
    /// be rendered (presentation falls back to plain text).
    ///
    /// Explicit symbologies render in their own encoding. Values scanned as
    /// (or without) an encodable type fall back to the universally scannable
    /// GS1 encodings, then Code 128.
    static func presentationBarcode(
        value: String,
        symbology: String?
    ) -> PresentationBarcode? {
        // 2D first: a QR card stays QR even if its value looks like a GS1 code.
        if symbology == "QR Code" {
            return qrCode(for: value).map {
                PresentationBarcode.qr(image: $0.image, moduleCount: $0.moduleCount)
            }
        }
        if symbology == "ITF" || symbology == "ITF-14" {
            return itfModules(value).map {
                .linear(modules: $0, quietModules: itfQuietModules,
                        nominalModuleWidthMM: itfNominalModuleWidthMM)
            }
        }
        if symbology == "Code 39" {
            return code39Modules(value).map {
                .linear(modules: $0, quietModules: code39QuietModules,
                        nominalModuleWidthMM: nominalModuleWidthMM)
            }
        }
        if symbology == "Code 128" {
            return code128Modules(value).map {
                .linear(modules: $0, quietModules: code128QuietModules,
                        nominalModuleWidthMM: nominalModuleWidthMM)
            }
        }
        // symbology == nil or a scanned type with no encoder of its own
        // (UPC-E, Code 93, Codabar, PDF417, …): try GS1, then Code 128.
        if let ean13 = ean13Path(value: value, symbology: symbology) {
            return .linear(modules: ean13, quietModules: ean13QuietModules,
                           nominalModuleWidthMM: nominalModuleWidthMM)
        }
        if value.count == 8, let ean8 = ean8Modules(value) {
            return .linear(modules: ean8, quietModules: ean8QuietModules,
                           nominalModuleWidthMM: nominalModuleWidthMM)
        }
        return code128Modules(value).map {
            .linear(modules: $0, quietModules: code128QuietModules,
                    nominalModuleWidthMM: nominalModuleWidthMM)
        }
    }

    private static func ean13Path(value: String, symbology: String?) -> [Bool]? {
        var ean13 = value
        if value.count == 12, symbology == "UPC-A" || symbology == nil {
            ean13 = "0" + value
        }
        return ean13Modules(ean13)
    }

    /// Encodes a 13-digit EAN-13 value into its 95-module pattern.
    static func ean13Modules(_ value: String) -> [Bool]? {
        guard value.count == 13,
              let digits = asciiDigits(value),
              BarcodeValidation.hasValidGS1CheckDigit(value)
        else { return nil }

        var modules: [Bool] = []
        modules.reserveCapacity(ean13ModuleCount)
        var encodedCount = 0

        func appendGuard(_ pattern: String) {
            for character in pattern {
                modules.append(character == "1")
                encodedCount += 1
            }
        }

        func appendDigit(_ digit: Int, from table: [String]) {
            for character in table[digit] {
                modules.append(character == "1")
                encodedCount += 1
            }
        }

        // Left guard: 101
        appendGuard("101")

        // First digit selects the L/G parity pattern for the six left digits.
        let parity = Array(parityPatterns[digits[0]])
        for (index, digit) in digits[1...6].enumerated() {
            appendDigit(digit, from: parity[index] == "L" ? lCodes : gCodes)
        }

        // Center guard: 01010
        appendGuard("01010")

        // Right digits, all from the R table.
        for digit in digits[7...12] {
            appendDigit(digit, from: rCodes)
        }

        // Right guard: 101
        appendGuard("101")

        precondition(encodedCount == ean13ModuleCount)
        return modules
    }

    /// Encodes an 8-digit EAN-8 value into its 67-module pattern:
    /// guard + 4 L digits + center guard + 4 R digits + guard.
    static func ean8Modules(_ value: String) -> [Bool]? {
        guard value.count == 8,
              let digits = asciiDigits(value),
              BarcodeValidation.hasValidGS1CheckDigit(value)
        else { return nil }

        var modules: [Bool] = []
        func append(_ pattern: String) { modules.append(contentsOf: pattern.map { $0 == "1" }) }

        append("101")
        for digit in digits[0...3] { append(lCodes[digit]) }
        append("01010")
        for digit in digits[4...7] { append(rCodes[digit]) }
        append("101")
        return modules
    }

    // MARK: - ITF (Interleaved 2 of 5) / ITF-14

    /// Encodes an even-length digit string into its ITF module pattern.
    /// Each digit pair interleaves the first digit into the bars and the
    /// second into the spaces; every digit is 5 elements, exactly 2 wide
    /// (3 modules each), the rest narrow (1 module).
    /// A 14-digit value is an ITF-14 and must carry a valid GS1 check digit
    /// (scanners reject the symbol otherwise).
    static func itfModules(_ value: String) -> [Bool]? {
        guard value.count >= 2, value.count % 2 == 0,
              let digits = asciiDigits(value)
        else { return nil }
        if value.count == 14 && !BarcodeValidation.hasValidGS1CheckDigit(value) {
            return nil
        }

        var modules: [Bool] = []
        // Start: narrow bar, narrow space, narrow bar, narrow space.
        modules.append(contentsOf: [true, false, true, false])
        for pair in stride(from: 0, to: digits.count, by: 2) {
            let bars = Array(itfWidePatterns[digits[pair]])
            let spaces = Array(itfWidePatterns[digits[pair + 1]])
            for i in 0..<5 {
                modules.append(contentsOf: Array(repeating: true, count: bars[i] == "1" ? 3 : 1))
                modules.append(contentsOf: Array(repeating: false, count: spaces[i] == "1" ? 3 : 1))
            }
        }
        // Stop: wide bar, narrow space, narrow bar.
        modules.append(contentsOf: [true, true, true, false, true])
        return modules
    }

    /// Which of the 5 elements are wide ('1') for each digit: bars carry the
    /// first digit of a pair, spaces the second.
    private static let itfWidePatterns = [
        "00110",  // 0: NNWWN
        "10001",  // 1: WNNNW
        "01001",  // 2: NWNNW
        "11000",  // 3: WWNNN
        "00101",  // 4: NNWNW
        "10100",  // 5: WNWNN
        "01100",  // 6: NWWNN
        "00011",  // 7: NNNWW
        "10010",  // 8: WNNWN
        "01010",  // 9: NWNWN
    ]

    // MARK: - QR Code

    /// The reserved prefix marking a base64-encoded binary QR payload.
    /// Stored in the plain `barcodeValue` string so decks stay importable
    /// on every app version: old versions show it as text, new ones render
    /// the original bytes.
    static let base64Prefix = "base64,"

    /// Decodes the payload of a `base64,…` value, or `nil` when malformed.
    static func decodeBase64Payload(_ value: String) -> Data? {
        guard value.hasPrefix(base64Prefix), value.count > base64Prefix.count else {
            return nil
        }
        // ignoreUnknownCharacters tolerates the line wraps some encoders insert.
        return Data(
            base64Encoded: String(value.dropFirst(base64Prefix.count)),
            options: [.ignoreUnknownCharacters]
        )
    }

    /// Generates a QR code image (error correction level M) via CoreImage.
    /// Returns the image and its module count — the generator emits one
    /// pixel per module with no quiet zone (the renderer reserves it).
    /// A `base64,…` value is decoded and encoded byte-for-byte; nil when
    /// the value is empty, malformed, or too long for a QR symbol.
    static func qrCode(for value: String) -> (image: CGImage, moduleCount: Int)? {
        guard !value.isEmpty else { return nil }
        let payload: Data
        if value.hasPrefix(base64Prefix) {
            guard let bytes = decodeBase64Payload(value) else { return nil }
            payload = bytes
        } else {
            guard let utf8 = value.data(using: .utf8) else { return nil }
            payload = utf8
        }
        guard payload.count <= 2331,  // QR byte-mode capacity, version 40 at level M
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }
        filter.setValue(payload, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let image = ciContext.createCGImage(output, from: output.extent),
              image.width > 0, image.width == image.height
        else { return nil }
        return (image, image.width)
    }

    // MARK: - Encoding tables (GS1 EAN-13)

    /// L (odd) patterns for digits 0–9, 7 modules each.
    private static let lCodes = [
        "0001101", "0011001", "0010011", "0111101", "0100011",
        "0110001", "0101111", "0111011", "0110111", "0001011",
    ]

    /// G (even) patterns for digits 0–9.
    private static let gCodes = [
        "0100111", "0110011", "0011011", "0100001", "0011101",
        "0111001", "0000101", "0010001", "0001001", "0010111",
    ]

    /// R patterns for digits 0–9 (complements of the L patterns).
    private static let rCodes = [
        "1110010", "1100110", "1101100", "1000010", "1011100",
        "1001110", "1010000", "1000100", "1001000", "1110100",
    ]

    /// For each first digit (0–9), which table (L or G) encodes each of the
    /// six left-hand digits.
    private static let parityPatterns = [
        "LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
        "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL",
    ]

    // MARK: - Code 128 (Code Set B)

    /// Encodes a printable-ASCII value (Code Set B) into its module pattern:
    /// start B + data + checksum + stop.
    static func code128Modules(_ value: String) -> [Bool]? {
        guard !value.isEmpty,
              let values = code128Values(value)
        else { return nil }

        var symbols: [Int] = [code128StartB]
        symbols.append(contentsOf: values)

        // Checksum: (start + Σ position·value) mod 103, positions from 1.
        var checksum = code128StartB
        for (position, value) in values.enumerated() {
            checksum += (position + 1) * value
        }
        symbols.append(checksum % 103)
        symbols.append(code128Stop)

        var modules: [Bool] = []
        // Data symbols use 11 modules each; the stop symbol adds 13.
        modules.reserveCapacity((symbols.count - 1) * 11 + 13)
        for symbol in symbols {
            append(widths: code128Widths[symbol], to: &modules)
        }
        return modules
    }

    private static let code128StartB = 104
    private static let code128Stop = 106

    private static func code128Values(_ value: String) -> [Int]? {
        var values: [Int] = []
        values.reserveCapacity(value.count)
        for character in value.unicodeScalars {
            // Code Set B covers ASCII 32–126 (space through ~).
            guard character.value >= 32, character.value <= 126 else { return nil }
            values.append(Int(character.value) - 32)
        }
        return values
    }

    private static func append(widths: String, to modules: inout [Bool]) {
        // Widths alternate bar/space, starting with a bar.
        var isBar = true
        for character in widths {
            for _ in 0..<(character.wholeNumberValue ?? 0) {
                modules.append(isBar)
            }
            isBar.toggle()
        }
    }

    /// Code 128 element widths (bar/space runs, 11 modules per symbol).
    /// Indices 0–106; the stop symbol (106) has a 7th trailing bar.
    private static let code128Widths = [
        "212222", "222122", "222221", "121223", "121322", "131222",
        "122213", "122312", "132212", "221213", "221312", "231212",
        "112232", "122132", "122231", "113222", "123122", "123221",
        "223211", "221132", "221231", "213212", "223112", "312131",
        "311222", "321122", "321221", "312212", "322112", "322211",
        "212123", "212321", "232121", "111323", "131123", "131321",
        "112313", "132113", "132311", "211313", "231113", "231311",
        "112133", "112331", "132131", "113123", "113321", "133121",
        "313121", "211331", "231131", "213113", "213311", "213131",
        "311123", "311321", "331121", "312113", "312311", "332111",
        "314111", "221411", "431111", "111224", "111422", "121124",
        "121421", "141122", "141221", "112214", "112412", "122114",
        "122411", "142112", "142211", "241211", "221114", "413111",
        "241112", "134111", "111242", "121142", "121241", "114212",
        "124112", "124211", "411212", "421112", "421211", "212141",
        "214121", "412121", "111143", "111341", "131141", "114113",
        "114311", "411113", "411311", "113141", "114131", "311141",
        "411131", "211412", "211214", "211232", "2331112",
    ]

    // MARK: - Code 39

    /// Internal so BarcodeValidation can validate manual entry against the
    /// exact charset the encoder accepts.
    static let code39AllowedCharacters = Set(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%"
    )

    /// Encodes a value using Code 39 (the symbology common on loyalty and
    /// health-insurance cards). Each symbol is 9 elements (5 bars, 4 spaces,
    /// exactly 3 wide) plus a narrow inter-character gap; `*` is the
    /// start/stop symbol.
    static func code39Modules(_ value: String) -> [Bool]? {
        let characters = Array(value.uppercased())
        guard !characters.isEmpty,
              characters.allSatisfy({ code39AllowedCharacters.contains($0) })
        else { return nil }

        var modules: [Bool] = []
        let symbols = ["*"] + characters.map(String.init) + ["*"]
        for (index, symbol) in symbols.enumerated() {
            if index > 0 {
                modules.append(false)  // narrow inter-character gap
            }
            appendCode39(widths: code39Patterns[symbol]!, to: &modules)
        }
        return modules
    }

    /// Exposed for testing: sorted (symbol, 9-element pattern) pairs.
    static func code39PatternsWithMetadata() -> [(symbol: String, pattern: String)] {
        code39Patterns.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private static func appendCode39(widths: String, to modules: inout [Bool]) {
        // Elements alternate bar/space, starting with a bar; 'w' = 3× wide.
        var isBar = true
        for element in widths {
            for _ in 0..<(element == "w" ? 3 : 1) {
                modules.append(isBar)
            }
            isBar.toggle()
        }
    }

    /// Code 39 element patterns ('n' = narrow, 'w' = wide), 9 elements each:
    /// bar, space, bar, space, bar, space, bar, space, bar.
    private static let code39Patterns = [
        "0": "nnnwwnwnn", "1": "wnnwnnnnw", "2": "nnwwnnnnw",
        "3": "wnwwnnnnn", "4": "nnnwwnnnw", "5": "wnnwwnnnn",
        "6": "nnwwwnnnn", "7": "nnnwnnwnw", "8": "wnnwnnwnn",
        "9": "nnwwnnwnn",
        "A": "wnnnnwnnw", "B": "nnwnnwnnw", "C": "wnwnnwnnn",
        "D": "nnnnwwnnw", "E": "wnnnwwnnn", "F": "nnwnwwnnn",
        "G": "nnnnnwwnw", "H": "wnnnnwwnn", "I": "nnwnnwwnn",
        "J": "nnnnwwwnn", "K": "wnnnnnnww", "L": "nnwnnnnww",
        "M": "wnwnnnnwn", "N": "nnnnwnnww", "O": "wnnnwnnwn",
        "P": "nnwnwnnwn", "Q": "nnnnnnwww", "R": "wnnnnnwwn",
        "S": "nnwnnnwwn", "T": "nnnnwnwwn", "U": "wwnnnnnnw",
        "V": "nwwnnnnnw", "W": "wwwnnnnnn", "X": "nwnnwnnnw",
        "Y": "wwnnwnnnn", "Z": "nwwnwnnnn",
        "-": "nwnnnnwnw", ".": "wwnnnnwnn", " ": "nwwnnnwnn",
        "$": "nwnwnwnnn", "/": "nwnwnnnwn", "+": "nwnnnwnwn",
        "%": "nnnwnwnwn",
        "*": "nwnnwnwnn",
    ]

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
