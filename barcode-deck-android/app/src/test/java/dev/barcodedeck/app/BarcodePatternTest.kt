package dev.barcodedeck.app

import dev.barcodedeck.app.data.BarcodePattern
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

    // MARK: - Code 128

    @Test fun `code128 A123456789 has 145 modules`() {
        val result = BarcodePattern.modulesForPresentation("A123456789", "Code 128")
        assertNotNull(result)
        assertEquals(145, result!!.first.size)
        assertEquals(bools("11010010000"), result.first.subList(0, 11))
        assertEquals(bools("1100011101011"), result.first.subList(132, 145))
    }

    @Test fun `upc-a renders as zero-padded ean-13`() {
        val upcA = BarcodePattern.modulesForPresentation("036000291452", "UPC-A")!!.first
        assertEquals(BarcodePattern.ean13Modules("0036000291452"), upcA)
    }

    @Test fun `12-digit code128 not misrendered as upc-a`() {
        val result = BarcodePattern.modulesForPresentation("036000291452", "Code 128")!!.first
        assertTrue(result != BarcodePattern.ean13Modules("0036000291452"))
    }

    @Test fun `invalid 13 digits fall back to code128`() {
        assertNotNull(BarcodePattern.modulesForPresentation("1234567890123", null))
    }

    // MARK: - Code 39

    @Test fun `code39 patterns are well formed`() {
        for ((symbol, pattern) in BarcodePattern.code39PatternsWithMetadata()) {
            assertTrue("'$symbol' length ${pattern.length}", pattern.length == 9)
            assertTrue("'$symbol' wide count", pattern.count { it == 'w' } == 3)
        }
    }

    @Test fun `code39 codice fiscale module count`() {
        val result = BarcodePattern.modulesForPresentation("GMMNDR78E17A271Q", "Code 39")
        assertNotNull(result)
        assertEquals(287, result!!.first.size)
        assertEquals(BarcodePattern.CODE39_QUIET_MODULES, result.second)
    }

    @Test fun `code39 is case insensitive`() =
        assertEquals(BarcodePattern.code39Modules("abc"), BarcodePattern.code39Modules("ABC"))

    @Test fun `code39 rejects out-of-set characters`() = assertNull(BarcodePattern.code39Modules("café"))
}
