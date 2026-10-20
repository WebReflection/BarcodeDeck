package dev.barcodedeck.app.data

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/**
 * Encodes barcode values into drawable patterns.
 * Kotlin port of the iOS BarcodePattern — same tables, same test vectors.
 *
 * Renders EAN-13, EAN-8, UPC-A (encoded as EAN-13 with leading 0), Code 128
 * (Code Set B), Code 39, ITF (incl. ITF-14) and QR codes.
 */
object BarcodePattern {

    const val EAN13_MODULE_COUNT = 95
    const val EAN13_QUIET_MODULES = 11
    const val EAN8_QUIET_MODULES = 7
    const val CODE128_QUIET_MODULES = 10
    const val CODE39_QUIET_MODULES = 10
    const val ITF_QUIET_MODULES = 10

    /** Nominal module width at 100% magnification, in millimetres (GS1). */
    const val NOMINAL_MODULE_WIDTH_MM = 0.33

    /** ITF-14's GS1 minimum X-dimension is 0.495 mm, so ITF renders with a
     *  larger nominal module than 1D retail codes. */
    const val ITF_NOMINAL_MODULE_WIDTH_MM = 0.495

    /** QR quiet zone (spec recommendation: 4 modules). */
    const val QR_QUIET_MODULES = 4

    private const val CODE128_START_B = 104
    private const val CODE128_STOP = 106

    /** A value resolved into something presentation mode can draw. */
    sealed interface PresentationBarcode {
        /** 1D symbol: module runs, quiet zone, nominal module width. */
        data class Linear(
            val modules: List<Boolean>,
            val quietModules: Int,
            val nominalModuleWidthMM: Double,
        ) : PresentationBarcode

        /** 2D symbol: row-major cell matrix (true = dark module). */
        data class Matrix(
            val cells: List<Boolean>,
            val columns: Int,
            val quietModules: Int,
        ) : PresentationBarcode
    }

    /**
     * Resolves a card into a drawable pattern, or null when the value cannot
     * be rendered (presentation falls back to plain text).
     *
     * Explicit symbologies render in their own encoding. Values scanned as
     * (or without) an encodable type fall back to the universally scannable
     * GS1 encodings, then Code 128.
     */
    fun presentationBarcode(value: String, symbology: String?): PresentationBarcode? {
        // 2D first: a QR card stays QR even if its value looks like a GS1 code.
        if (symbology == "QR Code") {
            return qrMatrix(value)?.let { (cells, columns) ->
                PresentationBarcode.Matrix(cells, columns, QR_QUIET_MODULES)
            }
        }
        if (symbology == "ITF" || symbology == "ITF-14") {
            return itfModules(value)?.let {
                PresentationBarcode.Linear(it, ITF_QUIET_MODULES, ITF_NOMINAL_MODULE_WIDTH_MM)
            }
        }
        if (symbology == "Code 39") {
            return code39Modules(value)?.let {
                PresentationBarcode.Linear(it, CODE39_QUIET_MODULES, NOMINAL_MODULE_WIDTH_MM)
            }
        }
        if (symbology == "Code 128") {
            return code128Modules(value)?.let {
                PresentationBarcode.Linear(it, CODE128_QUIET_MODULES, NOMINAL_MODULE_WIDTH_MM)
            }
        }
        // symbology == null or a scanned type with no encoder of its own
        // (UPC-E, Code 93, Codabar, PDF417, …): try GS1, then Code 128.
        ean13Path(value, symbology)?.let {
            return PresentationBarcode.Linear(it, EAN13_QUIET_MODULES, NOMINAL_MODULE_WIDTH_MM)
        }
        if (value.length == 8) {
            ean8Modules(value)?.let {
                return PresentationBarcode.Linear(it, EAN8_QUIET_MODULES, NOMINAL_MODULE_WIDTH_MM)
            }
        }
        return code128Modules(value)?.let {
            PresentationBarcode.Linear(it, CODE128_QUIET_MODULES, NOMINAL_MODULE_WIDTH_MM)
        }
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

    // MARK: - EAN-8

    /** Encodes an 8-digit EAN-8 value into its 67-module pattern:
     *  guard + 4 L digits + center guard + 4 R digits + guard. */
    fun ean8Modules(value: String): List<Boolean>? {
        if (value.length != 8) return null
        val digits = asciiDigits(value) ?: return null
        if (!BarcodeValidation.hasValidGS1CheckDigit(value)) return null

        val modules = ArrayList<Boolean>(67)
        fun appendGuard(pattern: String) = modules.addAll(pattern.map { it == '1' })
        fun appendDigit(digit: Int, table: List<String>) = modules.addAll(table[digit].map { it == '1' })

        appendGuard("101")
        for (digit in digits.slice(0..3)) appendDigit(digit, lCodes)
        appendGuard("01010")
        for (digit in digits.slice(4..7)) appendDigit(digit, rCodes)
        appendGuard("101")
        return modules
    }

    // MARK: - ITF (Interleaved 2 of 5) / ITF-14

    /**
     * Encodes an even-length digit string into its ITF module pattern.
     * Each digit pair interleaves the first digit into the bars and the
     * second into the spaces; every digit is 5 elements, exactly 2 wide.
     * A 14-digit value is an ITF-14 and must carry a valid GS1 check digit
     * (scanners reject the symbol otherwise).
     */
    fun itfModules(value: String): List<Boolean>? {
        if (value.length < 2 || value.length % 2 != 0) return null
        val digits = asciiDigits(value) ?: return null
        if (value.length == 14 && !BarcodeValidation.hasValidGS1CheckDigit(value)) return null

        val modules = mutableListOf<Boolean>()
        // Start: narrow bar, narrow space, narrow bar, narrow space.
        modules += listOf(true, false, true, false)
        for (pair in digits.indices step 2) {
            val bars = itfWidePatterns[digits[pair]]
            val spaces = itfWidePatterns[digits[pair + 1]]
            for (i in 0..4) {
                repeat(if (bars[i] == '1') 3 else 1) { modules += true }
                repeat(if (spaces[i] == '1') 3 else 1) { modules += false }
            }
        }
        // Stop: wide bar, narrow space, narrow bar.
        modules += listOf(true, true, true, false, true)
        return modules
    }

    /** Which of the 5 elements are wide ('1') for each digit: bars carry the
     *  first digit of a pair, spaces the second. */
    private val itfWidePatterns = listOf(
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
    )

    // MARK: - QR Code

    /** The reserved prefix marking a base64-encoded binary QR payload.
     *  Stored in the plain `barcodeValue` string so decks stay importable
     *  on every app version: old versions show it as text, new ones render
     *  the original bytes. */
    const val BASE64_PREFIX = "base64,"

    /** Decodes the payload of a `base64,…` value, or null when malformed. */
    fun decodeBase64Payload(value: String): ByteArray? {
        if (!value.startsWith(BASE64_PREFIX) || value.length <= BASE64_PREFIX.length) return null
        // Strip whitespace (some encoders wrap lines), then decode strictly
        // — anything that is not valid base64 must be rejected, not skipped.
        val cleaned = value.substring(BASE64_PREFIX.length).replace(Regex("\\s"), "")
        return try {
            java.util.Base64.getDecoder().decode(cleaned)
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    /**
     * Encodes a value into a square row-major QR cell matrix via ZXing
     * (error correction level M, no built-in margin — the quiet zone is
     * reserved by the renderer). Null when the value does not fit.
     *
     * A `base64,…` value is decoded and encoded byte-for-byte.
     */
    fun qrMatrix(value: String): Pair<List<Boolean>, Int>? {
        if (value.isEmpty()) return null
        val content: String
        val charset: String
        if (value.startsWith(BASE64_PREFIX)) {
            val bytes = decodeBase64Payload(value) ?: return null
            // One char per byte: with the ISO-8859-1 hint ZXing writes the
            // bytes verbatim into QR byte mode.
            content = String(bytes, Charsets.ISO_8859_1)
            charset = "ISO-8859-1"
        } else {
            content = value
            charset = "UTF-8"
        }
        val matrix = try {
            QRCodeWriter().encode(
                content,
                BarcodeFormat.QR_CODE,
                1,
                1,
                mapOf(
                    EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
                    EncodeHintType.CHARACTER_SET to charset,
                    EncodeHintType.MARGIN to 0,
                ),
            )
        } catch (e: Exception) {
            return null
        }
        val columns = matrix.width
        val cells = ArrayList<Boolean>(columns * matrix.height)
        for (y in 0 until matrix.height) {
            for (x in 0 until columns) cells += matrix[x, y]
        }
        return cells to columns
    }

    private fun asciiDigits(value: String): List<Int>? {
        if (value.isEmpty() || value.any { it !in '0'..'9' }) return null
        return value.map { it - '0' }
    }
}
