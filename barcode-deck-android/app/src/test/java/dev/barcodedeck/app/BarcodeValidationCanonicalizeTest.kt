package dev.barcodedeck.app

import dev.barcodedeck.app.data.BarcodeValidation
import org.junit.Assert.assertEquals
import org.junit.Test

/** Storage canonicalization: valid 12-digit UPC-A values are stored as
 *  their 0-padded EAN-13 equivalent, so decks match across platforms and
 *  imports de-duplicate (iOS Vision already reports scans padded). */
class BarcodeValidationCanonicalizeTest {

    private val upca = "400236325890"      // 12 digits, valid check digit
    private val padded = "0400236325890"   // its EAN-13 twin

    @Test
    fun `pads scanned UPC-A values to EAN-13`() {
        assertEquals(padded to "EAN-13", BarcodeValidation.canonicalize(upca, "UPC-A"))
    }

    @Test
    fun `pads auto-detected UPC-A values to EAN-13`() {
        assertEquals(padded to "EAN-13", BarcodeValidation.canonicalize(upca, null))
    }

    @Test
    fun `leaves an explicit Code 128 choice untouched`() {
        assertEquals(upca to "Code 128", BarcodeValidation.canonicalize(upca, "Code 128"))
    }

    @Test
    fun `leaves non-UPCA values untouched`() {
        assertEquals("5901234123457" to "EAN-13", BarcodeValidation.canonicalize("5901234123457", "EAN-13"))
        assertEquals("GMMNDR78E17Q" to null, BarcodeValidation.canonicalize("GMMNDR78E17Q", null))
    }

    @Test
    fun `does not pad values with a broken check digit`() {
        val broken = "400236325891"
        assertEquals(broken to "UPC-A", BarcodeValidation.canonicalize(broken, "UPC-A"))
    }

    @Test
    fun `canonical key matches both spellings of the same card`() {
        assertEquals(BarcodeValidation.canonicalKey(padded), BarcodeValidation.canonicalKey(upca))
        assertEquals(padded, BarcodeValidation.canonicalKey(upca))
        assertEquals("GMMNDR78E17Q", BarcodeValidation.canonicalKey("GMMNDR78E17Q"))
    }
}
