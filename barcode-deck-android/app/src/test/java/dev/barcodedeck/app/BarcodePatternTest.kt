package dev.barcodedeck.app

import com.google.zxing.BarcodeFormat
import com.google.zxing.oned.ITFWriter
import dev.barcodedeck.app.data.BarcodePattern
import dev.barcodedeck.app.data.BarcodePattern.PresentationBarcode
import dev.barcodedeck.app.data.BarcodeValidation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BarcodePatternTest {

    private fun bools(s: String) = s.map { it == '1' }

    // MARK: - Check digits

    @Test fun `valid EAN-13`() = assertTrue(BarcodeValidation.isValidEAN13("5901234123457"))
    @Test fun `invalid EAN-13 check digit`() = assertFalse(BarcodeValidation.isValidEAN13("5901234123458"))
    @Test fun `classify EAN-13`() = assertEquals("EAN-13", BarcodeValidation.classify("5901234123457"))
    @Test fun `valid UPC-A`() = assertTrue(BarcodeValidation.isValidUPCA("036000291452"))
    @Test fun `classify UPC-A`() = assertEquals("UPC-A", BarcodeValidation.classify("036000291452"))
    @Test fun `zero-padded UPC-A is EAN-13`() = assertEquals("EAN-13", BarcodeValidation.classify("0036000291452"))
    @Test fun `valid EAN-8`() = assertTrue(BarcodeValidation.isValidEAN8("24050012"))
    @Test fun `invalid EAN-8`() = assertFalse(BarcodeValidation.isValidEAN8("24050018"))
    @Test fun `canonical EAN-8`() = assertTrue(BarcodeValidation.isValidEAN8("96385074"))
    @Test fun `classify 14-digit GTIN as ITF-14`() =
        assertEquals("ITF-14", BarcodeValidation.classify("12345678901231"))
    @Test fun `alphanumeric does not classify`() = assertNull(BarcodeValidation.classify("A123456789"))

    // MARK: - EAN-13 structure

    @Test fun `ean13 has 95 modules and correct guards`() {
        val m = BarcodePattern.ean13Modules("4006381333931")
        assertNotNull(m)
        m!!
        assertEquals(95, m.size)
        assertEquals(bools("101"), m.subList(0, 3))
        assertEquals(bools("01010"), m.subList(45, 50))
        assertEquals(bools("101"), m.subList(92, 95))
        assertEquals(bools("0001101"), m.subList(3, 10))
        assertEquals(bools("0100111"), m.subList(10, 17))
        assertEquals(bools("1100110"), m.subList(85, 92))
    }

    @Test fun `ean13 5901234123457 parity`() {
        val m = BarcodePattern.ean13Modules("5901234123457")!!
        assertEquals(95, m.size)
        assertEquals(bools("0001011"), m.subList(3, 10))
        assertEquals(bools("0100111"), m.subList(10, 17))
    }

    @Test fun `bad check digit rejected`() = assertNull(BarcodePattern.ean13Modules("5901234123458"))
    @Test fun `non-digits rejected`() = assertNull(BarcodePattern.ean13Modules("400638133393A"))

    // MARK: - EAN-8

    @Test fun `ean8 has 67 modules and correct guards`() {
        val m = BarcodePattern.ean8Modules("24050012")!!
        assertEquals(67, m.size)
        assertEquals(bools("101"), m.subList(0, 3))
        assertEquals(bools("01010"), m.subList(31, 36))
        assertEquals(bools("101"), m.subList(64, 67))
        // First digit 2 (L code), last digit 2 (R code).
        assertEquals(bools("0010011"), m.subList(3, 10))
        assertEquals(bools("1101100"), m.subList(57, 64))
    }

    @Test fun `ean8 bad check digit rejected`() = assertNull(BarcodePattern.ean8Modules("24050018"))

    // MARK: - Code 128

    @Test fun `code128 A123456789 has 145 modules`() {
        val result = BarcodePattern.presentationBarcode("A123456789", "Code 128")
        assertTrue(result is PresentationBarcode.Linear)
        result as PresentationBarcode.Linear
        assertEquals(145, result.modules.size)
        assertEquals(bools("11010010000"), result.modules.subList(0, 11))
        assertEquals(bools("1100011101011"), result.modules.subList(132, 145))
    }

    @Test fun `upc-a renders as zero-padded ean-13`() {
        val upcA = BarcodePattern.presentationBarcode("036000291452", "UPC-A")
        assertTrue(upcA is PresentationBarcode.Linear)
        assertEquals(
            BarcodePattern.ean13Modules("0036000291452"),
            (upcA as PresentationBarcode.Linear).modules
        )
    }

    @Test fun `13-digit code128 not misrendered as ean-13`() {
        val result = BarcodePattern.presentationBarcode("4006381333931", "Code 128")
        assertTrue(result is PresentationBarcode.Linear)
        assertTrue(
            (result as PresentationBarcode.Linear).modules !=
                BarcodePattern.ean13Modules("4006381333931")
        )
    }

    @Test fun `invalid 13 digits fall back to code128`() {
        assertNotNull(BarcodePattern.presentationBarcode("1234567890123", null))
    }

    // MARK: - Code 39

    @Test fun `code39 patterns are well formed`() {
        for ((symbol, pattern) in BarcodePattern.code39PatternsWithMetadata()) {
            assertTrue("'$symbol' length ${pattern.length}", pattern.length == 9)
            assertTrue("'$symbol' wide count", pattern.count { it == 'w' } == 3)
        }
    }

    @Test fun `code39 codice fiscale module count`() {
        val result = BarcodePattern.presentationBarcode("GMMNDR78E17A271Q", "Code 39")
        assertTrue(result is PresentationBarcode.Linear)
        result as PresentationBarcode.Linear
        assertEquals(287, result.modules.size)
        assertEquals(BarcodePattern.CODE39_QUIET_MODULES, result.quietModules)
    }

    @Test fun `code39 is case insensitive`() =
        assertEquals(BarcodePattern.code39Modules("abc"), BarcodePattern.code39Modules("ABC"))

    @Test fun `code39 rejects out-of-set characters`() = assertNull(BarcodePattern.code39Modules("café"))

    // MARK: - ITF

    @Test fun `itf14 has 135 modules and correct guards`() {
        val m = BarcodePattern.itfModules("12345678901231")!!
        assertEquals(135, m.size)
        assertEquals(bools("1010"), m.subList(0, 4))
        assertEquals(bools("11101"), m.subList(130, 135))
    }

    @Test fun `itf rejects odd digit count and non-digits`() {
        assertNull(BarcodePattern.itfModules("12345"))
        assertNull(BarcodePattern.itfModules("1234A670"))
    }

    @Test fun `itf14 with bad check digit rejected`() =
        assertNull(BarcodePattern.itfModules("12345678901238"))

    @Test fun `plain ITF encodes without checksum validation`() =
        assertNotNull(BarcodePattern.itfModules("12345671"))

    /** Authoritative cross-check: our ITF tables must produce exactly the
     *  same modules as ZXing's reference encoder (quiet zone stripped). */
    @Test fun `itf matches zxing reference encoder`() {
        for (value in listOf("12345670", "96385074", "12345678901231")) {
            val modules = BarcodePattern.itfModules(value)!!
            // Request a wide matrix: the writer scales the symbol up and adds
            // its own quiet zone; we locate the symbol between the margins.
            val matrix = ITFWriter().encode(value, BarcodeFormat.ITF, 1000, 1)
            var first = -1
            var last = -1
            for (x in 0 until matrix.width) {
                if (matrix.get(x, 0)) {
                    if (first == -1) first = x
                    last = x
                }
            }
            val stripWidth = last - first + 1
            assertTrue("strip $stripWidth not divisible by ${modules.size}", stripWidth % modules.size == 0)
            val multiple = stripWidth / modules.size
            val reference = (0 until modules.size).map { matrix.get(first + it * multiple, 0) }
            assertEquals("mismatch for $value", modules, reference)
        }
    }

    @Test fun `scanned ITF routes to the ITF renderer`() {
        val result = BarcodePattern.presentationBarcode("12345678901231", "ITF-14")
        assertTrue(result is PresentationBarcode.Linear)
        result as PresentationBarcode.Linear
        assertEquals(BarcodePattern.ITF_QUIET_MODULES, result.quietModules)
        assertEquals(BarcodePattern.ITF_NOMINAL_MODULE_WIDTH_MM, result.nominalModuleWidthMM, 1e-9)
    }

    // MARK: - QR

    @Test fun `qr matrix is square`() {
        val (cells, columns) = BarcodePattern.qrMatrix("HELLO")!!
        assertTrue(cells.size % columns == 0)
        assertEquals(columns, cells.size / columns)
        assertTrue(columns >= 21)
    }

    @Test fun `qr rejects empty and oversized values`() {
        assertNull(BarcodePattern.qrMatrix(""))
        assertNull(BarcodePattern.qrMatrix("x".repeat(5000)))
    }

    @Test fun `qr card stays qr even when the value looks like ean-13`() {
        val result = BarcodePattern.presentationBarcode("4006381333931", "QR Code")
        assertTrue(result is PresentationBarcode.Matrix)
    }

    // MARK: - Fallbacks for scanned-but-unencodable types

    @Test fun `scanned codabar falls back to code128 bars`() {
        val result = BarcodePattern.presentationBarcode("A123456789", "Codabar")
        assertTrue(result is PresentationBarcode.Linear)
        assertEquals(145, (result as PresentationBarcode.Linear).modules.size)
    }

    @Test fun `scanned ean-8 renders as ean-8`() {
        val result = BarcodePattern.presentationBarcode("24050012", "EAN-8")
        assertTrue(result is PresentationBarcode.Linear)
        result as PresentationBarcode.Linear
        assertEquals(BarcodePattern.EAN8_QUIET_MODULES, result.quietModules)
        assertEquals(BarcodePattern.NOMINAL_MODULE_WIDTH_MM, result.nominalModuleWidthMM, 1e-9)
    }

    @Test fun `ean-8 with bad check digit falls back to code128`() {
        assertNotNull(BarcodePattern.presentationBarcode("24050018", "EAN-8"))
    }

    // MARK: - HTTP URL detection (presentation "open link" button)

    @Test fun `https url detected`() =
        assertEquals("https://example.com", BarcodeValidation.asHttpUrl("https://example.com"))

    @Test fun `http url detected case-insensitively after trimming`() =
        assertEquals("HTTP://example.com/x", BarcodeValidation.asHttpUrl("  HTTP://example.com/x "))

    @Test fun `non-http schemes never open`() {
        assertNull(BarcodeValidation.asHttpUrl("ftp://example.com"))
        assertNull(BarcodeValidation.asHttpUrl("javascript:alert(1)"))
        assertNull(BarcodeValidation.asHttpUrl("mailto:a@b.c"))
        assertNull(BarcodeValidation.asHttpUrl("intent://x"))
    }

    @Test fun `plain text is not a url`() =
        assertNull(BarcodeValidation.asHttpUrl("https.example.com"))

    // MARK: - Binary (base64) payloads

    @Test fun `base64 payload encodes and round-trips`() {
        val bytes = byteArrayOf(0x00, 0x01, 0x02, -1, -2, 0x41.toByte())
        val value = BarcodePattern.BASE64_PREFIX + java.util.Base64.getEncoder().encodeToString(bytes)
        assertNotNull(BarcodePattern.qrMatrix(value))
        assertTrue(BarcodePattern.decodeBase64Payload(value)!!.contentEquals(bytes))
    }

    @Test fun `malformed base64 rejected`() {
        assertNull(BarcodePattern.qrMatrix("base64,%%%"))
        assertNull(BarcodePattern.decodeBase64Payload("base64,%%%"))
        assertNull(BarcodePattern.decodeBase64Payload("base64,"))
        assertNull(BarcodePattern.decodeBase64Payload("just text"))
        assertEquals(
            "“base64,” values must continue with valid base64.",
            BarcodeValidation.manualTypeError("QR Code", "base64,%%%")
        )
    }

    @Test fun `valid base64 payload passes manual validation`() =
        assertNull(
            BarcodeValidation.manualTypeError(
                "QR Code", BarcodePattern.BASE64_PREFIX + "AAECAw=="
            )
        )

    // MARK: - Manual entry

    @Test fun `manual ITF rejects odd digits`() = assertEquals(
        "ITF needs an even number of digits (currently 5).",
        BarcodeValidation.manualTypeError("ITF", "12345")
    )

    @Test fun `manual ITF rejects letters`() =
        assertEquals("ITF uses digits only.", BarcodeValidation.manualTypeError("ITF", "1234A678"))

    @Test fun `manual ITF-14 with bad check digit is a hard error`() =
        assertTrue(
            BarcodeValidation.manualTypeError("ITF", "12345678901238")?.contains("check digit") == true
        )

    @Test fun `manual ITF accepts even digits`() =
        assertNull(BarcodeValidation.manualTypeError("ITF", "12345670"))

    @Test fun `manual QR Code accepts anything`() =
        assertNull(BarcodeValidation.manualTypeError("QR Code", "https://example.com/🎉"))

    @Test fun `auto resolves 14 digits to ITF-14`() =
        assertEquals("ITF-14", BarcodeValidation.resolveAutoSymbology("12345678901231"))
}
