import Foundation

/// Encodes barcode values into module patterns (`true` = bar, `false` = space).
/// v1 renders EAN-13 and UPC-A (UPC-A is encoded as EAN-13 with a leading 0 —
/// the bar patterns are identical).
enum BarcodePattern {

    /// Number of modules in a complete EAN-13 symbol.
    static let ean13ModuleCount = 95

    /// Nominal module width at 100% magnification, in millimetres (GS1).
    static let nominalModuleWidthMM = 0.33

    /// Reserved quiet zones for EAN-13, in modules (GS1: ≥ 11 left, ≥ 7 right).
    static let ean13QuietModules = 11

    /// Returns the module pattern for a value plus its required quiet zone
    /// (in modules), or `nil` when the value cannot be rendered.
    ///
    /// - 13 digits + valid check digit → EAN-13.
    /// - 12 digits + valid check digit → UPC-A, normalized to EAN-13
    ///   (only when the symbology is UPC-A or unknown, so a 12-digit
    ///   Code 128 is never misrendered).
    /// - Anything else that is printable ASCII → Code 128 (Code Set B),
    ///   when the symbology is Code 128 or unknown.
    static func modulesForPresentation(
        value: String,
        symbology: String?
    ) -> (modules: [Bool], quietModules: Int)? {
        if let ean13 = ean13Path(value: value, symbology: symbology) {
            return (ean13, ean13QuietModules)
        }
        if symbology == "Code 39", let code39 = code39Modules(value) {
            return (code39, code39QuietModules)
        }
        if symbology == "Code 128" || symbology == nil,
           let code128 = code128Modules(value)
        {
            return (code128, code128QuietModules)
        }
        return nil
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

    /// Quiet zone for Code 128, in modules (GS1 general standard: 10×).
    static let code128QuietModules = 10

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

    /// Quiet zone for Code 39, in modules (GS1 general standard: 10×).
    static let code39QuietModules = 10

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
