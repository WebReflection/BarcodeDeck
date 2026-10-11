package dev.barcodedeck.app

import dev.barcodedeck.app.data.BarcodeValidation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests for the manual-entry type selection: auto resolution, hard
 *  validation errors, and soft check-digit warnings. */
class BarcodeValidationManualTypeTest {

    // MARK: - Auto resolution

    @Test fun `auto resolves valid EAN-13`() =
        assertEquals("EAN-13", BarcodeValidation.resolveAutoSymbology("5901234123457"))

    @Test fun `auto resolves valid UPC-A`() =
        assertEquals("UPC-A", BarcodeValidation.resolveAutoSymbology("036000291452"))

    @Test fun `auto resolves valid EAN-8`() =
        assertEquals("EAN-8", BarcodeValidation.resolveAutoSymbology("24050012"))

    @Test fun `auto resolves letters to Code 128`() =
        assertEquals("Code 128", BarcodeValidation.resolveAutoSymbology("ABC-123"))

    @Test fun `auto resolves digits with bad check digit to Code 128`() =
        assertEquals("Code 128", BarcodeValidation.resolveAutoSymbology("5901234123458"))

    @Test fun `auto resolves non-encodable value to null`() =
        assertNull(BarcodeValidation.resolveAutoSymbology("héllo🎉"))

    @Test fun `auto resolves empty value to null`() =
        assertNull(BarcodeValidation.resolveAutoSymbology(""))

    // MARK: - Hard validation errors

    @Test fun `auto never hard-fails`() =
        assertNull(BarcodeValidation.manualTypeError(null, "anything 🎉"))

    @Test fun `EAN-13 rejects letters`() =
        assertEquals("EAN-13 uses digits only.", BarcodeValidation.manualTypeError("EAN-13", "1234ABCDE5678"))

    @Test fun `EAN-13 rejects wrong length`() =
        assertEquals(
            "EAN-13 needs exactly 13 digits (currently 5).",
            BarcodeValidation.manualTypeError("EAN-13", "12345")
        )

    @Test fun `UPC-A rejects wrong length`() =
        assertEquals(
            "UPC-A needs exactly 12 digits (currently 11).",
            BarcodeValidation.manualTypeError("UPC-A", "03600029145")
        )

    @Test fun `EAN-13 with valid check digit passes`() =
        assertNull(BarcodeValidation.manualTypeError("EAN-13", "5901234123457"))

    @Test fun `EAN-13 with bad check digit is a hard error mentioning the expected digit`() {
        val error = BarcodeValidation.manualTypeError("EAN-13", "5901234123458")
        assertTrue(error!!.startsWith("Check digit doesn't match — expected 7."))
    }

    @Test fun `UPC-A with bad check digit is a hard error`() = assertTrue(
        BarcodeValidation.manualTypeError("UPC-A", "036000291453")!!.startsWith("Check digit doesn't match")
    )

    @Test fun `gs1CheckDigit computes expected values`() {
        assertEquals(7, BarcodeValidation.gs1CheckDigit("590123412345"))
        assertEquals(2, BarcodeValidation.gs1CheckDigit("03600029145"))
        assertEquals(2, BarcodeValidation.gs1CheckDigit("2405001"))
    }

    @Test fun `Code 39 accepts its charset`() =
        assertNull(BarcodeValidation.manualTypeError("Code 39", "ABC-123. $/+%"))

    @Test fun `Code 39 rejects invalid characters`() {
        val error = BarcodeValidation.manualTypeError("Code 39", "AB@CD")
        assertTrue(error!!.startsWith("Code 39 can't encode: @"))
    }

    @Test fun `Code 39 invalid characters are deduplicated in order`() =
        assertEquals(listOf('@', '#'), BarcodeValidation.invalidCode39Characters("x@y#z"))

    @Test fun `Code 128 accepts printable ASCII`() =
        assertNull(BarcodeValidation.manualTypeError("Code 128", "Any ~thing 42!"))

    @Test fun `Code 128 rejects non-ASCII`() =
        assertEquals(
            "Code 128 needs plain ASCII characters.",
            BarcodeValidation.manualTypeError("Code 128", "héllo")
        )

    // MARK: - Option list

    @Test fun `auto is the first option and types are sorted`() {
        val options = BarcodeValidation.manualTypeOptions
        assertEquals(null, options.first())
        val names = options.subList(1, options.size).filterNotNull()
        assertEquals(names.sorted(), names)
    }
}
