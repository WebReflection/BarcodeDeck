package dev.barcodedeck.app.data

/**
 * Encodes barcode values into module patterns (true = bar, false = space).
 * Kotlin port of the iOS BarcodePattern — same tables, same test vectors.
 *
 * Renders EAN-13, UPC-A (encoded as EAN-13 with leading 0), Code 128
 * (Code Set B) and Code 39.
 */
object BarcodePattern {

    const val EAN13_MODULE_COUNT = 95
    const val EAN13_QUIET_MODULES = 11
    const val NOMINAL_MODULE_WIDTH_MM = 0.33
    const val CODE128_QUIET_MODULES = 10
    const val CODE39_QUIET_MODULES = 10

    private const val CODE128_START_B = 104
    private const val CODE128_STOP = 106

    /**
     * Returns the module pattern for a value plus its required quiet zone
     * (in modules), or null when the value cannot be rendered.
     */
    fun modulesForPresentation(value: String, symbology: String?): Pair<List<Boolean>, Int>? {
        ean13Path(value, symbology)?.let { return it to EAN13_QUIET_MODULES }
        if (symbology == "Code 39") code39Modules(value)?.let { return it to CODE39_QUIET_MODULES }
        if (symbology == "Code 128" || symbology == null) {
            code128Modules(value)?.let { return it to CODE128_QUIET_MODULES }
        }
        return null
    }

    private fun ean13Path(value: String, symbology: String?): List<Boolean>? {
        var ean13 = value
        if (value.length == 12 && (symbology == "UPC-A" || symbology == null)) {
            ean13 = "0$value"
        }
        return ean13Modules(ean13)
    }

    /** Encodes a 13-digit EAN-13 value into its 95-module pattern. */
    fun ean13Modules(value: String): List<Boolean>? {
        if (value.length != 13) return null
        val digits = asciiDigits(value) ?: return null
        if (!BarcodeValidation.hasValidGS1CheckDigit(value)) return null

        val modules = ArrayList<Boolean>(EAN13_MODULE_COUNT)
        var encoded = 0

        fun appendGuard(pattern: String) {
            for (c in pattern) { modules += (c == '1'); encoded++ }
        }
        fun appendDigit(digit: Int, table: List<String>) {
            for (c in table[digit]) { modules += (c == '1'); encoded++ }
        }

        appendGuard("101")
        val parity = parityPatterns[digits[0]]
        for ((index, digit) in digits.slice(1..6).withIndex()) {
            appendDigit(digit, if (parity[index] == 'L') lCodes else gCodes)
        }
        appendGuard("01010")
        for (digit in digits.slice(7..12)) appendDigit(digit, rCodes)
        appendGuard("101")

        check(encoded == EAN13_MODULE_COUNT)
        return modules
    }

    // MARK: - Encoding tables (GS1 EAN-13)

    private val lCodes = listOf(
        "0001101", "0011001", "0010011", "0111101", "0100011",
        "0110001", "0101111", "0111011", "0110111", "0001011",
    )
    private val gCodes = listOf(
        "0100111", "0110011", "0011011", "0100001", "0011101",
        "0111001", "0000101", "0010001", "0001001", "0010111",
    )
    private val rCodes = listOf(
        "1110010", "1100110", "1101100", "1000010", "1011100",
        "1001110", "1010000", "1000100", "1001000", "1110100",
    )
    private val parityPatterns = listOf(
        "LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
        "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL",
    )

    // MARK: - Code 128 (Code Set B)

    fun code128Modules(value: String): List<Boolean>? {
        if (value.isEmpty()) return null
        val values = code128Values(value) ?: return null

        val symbols = mutableListOf(CODE128_START_B)
        symbols += values
        var checksum = CODE128_START_B
        values.forEachIndexed { position, v -> checksum += (position + 1) * v }
        symbols += checksum % 103
        symbols += CODE128_STOP

        val modules = ArrayList<Boolean>((symbols.size - 1) * 11 + 13)
        for (symbol in symbols) appendWidths(code128Widths[symbol], modules)
        return modules
    }

    private fun code128Values(value: String): List<Int>? {
        val out = mutableListOf<Int>()
        for (c in value) {
            val code = c.code
            if (code < 32 || code > 126) return null
            out += code - 32
        }
        return out
    }

    private fun appendWidths(widths: String, modules: MutableList<Boolean>) {
        var isBar = true
        for (c in widths) {
            repeat(c - '0') { modules += isBar }
            isBar = !isBar
        }
    }

    private val code128Widths = listOf(
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
    )

    // MARK: - Code 39

    /** Internal so BarcodeValidation can validate manual entry against the
     *  exact charset the encoder accepts. */
    val code39Allowed = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%".toSet()

    fun code39Modules(value: String): List<Boolean>? {
        val characters = value.uppercase().toList()
        if (characters.isEmpty() || characters.any { it !in code39Allowed }) return null

        val modules = mutableListOf<Boolean>()
        val symbols = listOf("*") + characters.map { it.toString() } + listOf("*")
        symbols.forEachIndexed { index, symbol ->
            if (index > 0) modules += false  // narrow inter-character gap
            appendCode39(code39Patterns[symbol]!!, modules)
        }
        return modules
    }

    private fun appendCode39(widths: String, modules: MutableList<Boolean>) {
        var isBar = true
        for (element in widths) {
            repeat(if (element == 'w') 3 else 1) { modules += isBar }
            isBar = !isBar
        }
    }

    /** Exposed for testing: sorted (symbol, 9-element pattern) pairs. */
    fun code39PatternsWithMetadata(): List<Pair<String, String>> =
        code39Patterns.entries.sortedBy { it.key }.map { it.key to it.value }

    private val code39Patterns = mapOf(
        "0" to "nnnwwnwnn", "1" to "wnnwnnnnw", "2" to "nnwwnnnnw",
        "3" to "wnwwnnnnn", "4" to "nnnwwnnnw", "5" to "wnnwwnnnn",
        "6" to "nnwwwnnnn", "7" to "nnnwnnwnw", "8" to "wnnwnnwnn",
        "9" to "nnwwnnwnn",
        "A" to "wnnnnwnnw", "B" to "nnwnnwnnw", "C" to "wnwnnwnnn",
        "D" to "nnnnwwnnw", "E" to "wnnnwwnnn", "F" to "nnwnwwnnn",
        "G" to "nnnnnwwnw", "H" to "wnnnnwwnn", "I" to "nnwnnwwnn",
        "J" to "nnnnwwwnn", "K" to "wnnnnnnww", "L" to "nnwnnnnww",
        "M" to "wnwnnnnwn", "N" to "nnnnwnnww", "O" to "wnnnwnnwn",
        "P" to "nnwnwnnwn", "Q" to "nnnnnnwww", "R" to "wnnnnnwwn",
        "S" to "nnwnnnwwn", "T" to "nnnnwnwwn", "U" to "wwnnnnnnw",
        "V" to "nwwnnnnnw", "W" to "wwwnnnnnn", "X" to "nwnnwnnnw",
        "Y" to "wwnnwnnnn", "Z" to "nwwnwnnnn",
        "-" to "nwnnnnwnw", "." to "wwnnnnwnn", " " to "nwwnnnwnn",
        "$" to "nwnwnwnnn", "/" to "nwnwnnnwn", "+" to "nwnnnwnwn",
        "%" to "nnnwnwnwn",
        "*" to "nwnnwnwnn",
    )

    private fun asciiDigits(value: String): List<Int>? {
        if (value.isEmpty() || value.any { it !in '0'..'9' }) return null
        return value.map { it - '0' }
    }
}
