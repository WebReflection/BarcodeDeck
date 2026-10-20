package dev.barcodedeck.app.data

/**
 * Barcode value validation (GS1 check digits) and symbology classification.
 * Kotlin port of the iOS BarcodeValidation — same rules, same test vectors.
 */
object BarcodeValidation {

    /** Validates the final (check) digit of a GS1-style numeric code
     *  (EAN-8, UPC-A, EAN-13). Weights alternate 3/1 from the right. */
    fun hasValidGS1CheckDigit(value: String): Boolean {
        if (value.isEmpty() || !value.all { it in '0'..'9' }) return false
        val expected = value.last().digitToInt()
        var sum = 0
        var weight = 3
        for (i in value.length - 2 downTo 0) {
            sum += (value[i] - '0') * weight
            weight = if (weight == 3) 1 else 3
        }
        return (10 - sum % 10) % 10 == expected
    }

    fun isValidEAN13(value: String) = value.length == 13 && hasValidGS1CheckDigit(value)
    fun isValidUPCA(value: String) = value.length == 12 && hasValidGS1CheckDigit(value)
    fun isValidEAN8(value: String) = value.length == 8 && hasValidGS1CheckDigit(value)

    /** Classifies an ASCII-digit value into a symbology name when its length
     *  and check digit match a known GS1 format; otherwise null. */
    fun classify(value: String): String? = when {
        value.length == 13 && hasValidGS1CheckDigit(value) -> "EAN-13"
        value.length == 12 && hasValidGS1CheckDigit(value) -> "UPC-A"
        value.length == 8 && hasValidGS1CheckDigit(value) -> "EAN-8"
        value.length == 14 && hasValidGS1CheckDigit(value) -> "ITF-14"
        else -> null
    }

    /** Computes the GS1 check digit for a numeric payload (the value without
     *  its final digit: 12 for EAN-13, 11 for UPC-A, 7 for EAN-8). */
    fun gs1CheckDigit(payload: String): Int? {
        if (payload.isEmpty() || !payload.all { it in '0'..'9' }) return null
        var sum = 0
        var weight = 3
        for (i in payload.length - 1 downTo 0) {
            sum += (payload[i] - '0') * weight
            weight = if (weight == 3) 1 else 3
        }
        return (10 - sum % 10) % 10
    }

    /** Canonical storage form: a valid 12-digit UPC-A value is stored as its
     *  0-padded EAN-13 equivalent (UPC-A *is* EAN-13 with a leading 0 — the
     *  rendered bars are identical). iOS already stores this canonical form
     *  because Vision reports UPC-A scans padded; doing it here keeps decks
     *  byte-identical across platforms so import de-duplication works.
     *  Only applies when the symbology is UPC-A or unknown — an explicit
     *  Code 128 / Code 39 choice is deliberate and stays untouched. */
    fun canonicalize(value: String, symbology: String?): Pair<String, String?> =
        if ((symbology == "UPC-A" || symbology == null) && isValidUPCA(value)) {
            "0$value" to "EAN-13"
        } else {
            value to symbology
        }

    /** De-duplication key for a barcode value: the canonical EAN-13 form of
     *  valid 12-digit UPC-A values, the value itself otherwise. */
    fun canonicalKey(value: String): String =
        if (isValidUPCA(value)) "0$value" else value

    /** The trimmed value as an http(s) URL, or null. This is the only
     *  scheme the app will ever open (presentation mode's "open link"
     *  button) — QR payloads can carry javascript:, intent:, mailto: etc.,
     *  and those must never be launched. */
    fun asHttpUrl(value: String): String? =
        value.trim().takeIf {
            it.startsWith("http://", ignoreCase = true) ||
                it.startsWith("https://", ignoreCase = true)
        }

    // MARK: - Manual entry

    /** Types offered for manual entry, alphabetically, with Auto-detect
     *  (null) first. Only symbologies the app can render in presentation
     *  mode are offered — scanned cards may carry any scanned type. */
    val manualTypeOptions: List<String?> =
        listOf(null, "Code 128", "Code 39", "EAN-13", "ITF", "QR Code", "UPC-A")

    /** Resolves the Auto-detect selection into the symbology to store: a
     *  valid GS1 classification when the digits match one, otherwise Code 128
     *  (the universal, renderable fallback) — or null when the value cannot
     *  be encoded at all (presentation will show it as plain text). */
    fun resolveAutoSymbology(value: String): String? =
        classify(value) ?: if (isCode128Encodable(value)) "Code 128" else null

    /** Whether every character is ASCII 32–126, i.e. Code 128 Code Set B. */
    fun isCode128Encodable(value: String): Boolean =
        value.isNotEmpty() && value.all { it.code in 32..126 }

    /** Characters of value that Code 39 cannot encode (case-insensitive),
     *  deduplicated in order of first appearance. */
    fun invalidCode39Characters(value: String): List<Char> {
        val seen = HashSet<Char>()
        val invalid = mutableListOf<Char>()
        for (c in value.uppercase()) {
            if (c !in BarcodePattern.code39Allowed && seen.add(c)) invalid += c
        }
        return invalid
    }

    /** Hard validation for a manually chosen type: an error message when the
     *  value can never be encoded as that type, null when OK. A GS1 value
     *  with a wrong check digit is also a hard error: it could neither be
     *  rendered nor scanned, so saving it would only create a dead card. */
    fun manualTypeError(type: String?, value: String): String? {
        if (type == null) return null  // Auto-detect never hard-fails
        return when (type) {
            "EAN-13" -> when {
                !value.all { it in '0'..'9' } -> "EAN-13 uses digits only."
                value.length != 13 -> "EAN-13 needs exactly 13 digits (currently ${value.length})."
                !hasValidGS1CheckDigit(value) ->
                    "Check digit doesn't match — expected ${gs1CheckDigit(value.take(12))}. " +
                        "Double-check the digits before saving."
                else -> null
            }
            "UPC-A" -> when {
                !value.all { it in '0'..'9' } -> "UPC-A uses digits only."
                value.length != 12 -> "UPC-A needs exactly 12 digits (currently ${value.length})."
                !hasValidGS1CheckDigit(value) ->
                    "Check digit doesn't match — expected ${gs1CheckDigit(value.take(11))}. " +
                        "Double-check the digits before saving."
                else -> null
            }
            "Code 39" -> invalidCode39Characters(value).takeIf { it.isNotEmpty() }?.let {
                "Code 39 can't encode: ${it.joinToString(", ")}."
            }
            "Code 128" -> if (isCode128Encodable(value)) null
                else "Code 128 needs plain ASCII characters."
            "ITF" -> when {
                !value.all { it in '0'..'9' } -> "ITF uses digits only."
                value.length % 2 != 0 ->
                    "ITF needs an even number of digits (currently ${value.length})."
                value.length == 14 && !hasValidGS1CheckDigit(value) ->
                    "A 14-digit ITF (ITF-14) needs a valid check digit — " +
                        "expected ${gs1CheckDigit(value.take(13))}. Double-check the digits."
                else -> null
            }
            "QR Code" -> if (value.startsWith(BarcodePattern.BASE64_PREFIX) &&
                BarcodePattern.decodeBase64Payload(value) == null
            ) {
                "“base64,” values must continue with valid base64."
            } else null  // Any text encodes; too-long values fall back to text.
            else -> null
        }
    }
}
