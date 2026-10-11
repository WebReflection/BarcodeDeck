package dev.barcodedeck.app

import dev.barcodedeck.app.data.Card
import dev.barcodedeck.app.data.CardTransfer
import dev.barcodedeck.app.data.TransferException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class CardTransferTest {

    @Test
    fun `round trip preserves cards`() {
        val cards = listOf(
            Card(
                name = "Green Grocery", description = "Loyalty",
                barcodeValue = "5901234123457", symbology = "EAN-13",
                createdAt = 1700000000000L
            ),
            Card(
                name = "Codice Fiscale", description = null,
                barcodeValue = "GMMNDR78E17Q", symbology = "Code 39",
                createdAt = 1700000100000L
            )
        )
        val json = CardTransfer.export(cards)
        assertTrue(json.contains("barcodedeck-export"))

        val decoded = CardTransfer.decode(json)
        assertEquals(2, decoded.cards.size)
        assertEquals("Codice Fiscale", decoded.cards[1].name)
        assertEquals(null, decoded.cards[1].description)
        assertEquals("GMMNDR78E17Q", decoded.cards[1].barcodeValue)
        // ISO-8601 round trip: epoch millis survive exactly
        assertEquals(1700000100000L, decoded.cards[1].createdAt)
    }

    @Test
    fun `legacy cardbox type is accepted`() {
        val json = """{"type":"cardbox-export","version":1,"exportedAt":"2026-01-01T00:00:00Z","cards":[]}"""
        assertEquals(0, CardTransfer.decode(json).cards.size)
    }

    @Test
    fun `wrong type is rejected`() {
        val json = """{"type":"other","version":1,"exportedAt":"2026-01-01T00:00:00Z","cards":[]}"""
        try {
            CardTransfer.decode(json)
            fail("expected TransferException")
        } catch (e: TransferException) { /* expected */ }
    }

    @Test
    fun `future version is rejected`() {
        val json = """{"type":"barcodedeck-export","version":99,"exportedAt":"2026-01-01T00:00:00Z","cards":[]}"""
        try {
            CardTransfer.decode(json)
            fail("expected TransferException")
        } catch (e: TransferException) {
            assertTrue(e.message!!.contains("too new"))
        }
    }

    @Test
    fun `garbage is rejected`() {
        try {
            CardTransfer.decode("not json at all")
            fail("expected TransferException")
        } catch (e: TransferException) { /* expected */ }
    }

    @Test
    fun `import plan skips duplicates by barcode value`() {
        val export = CardTransfer.decode(
            """{"type":"barcodedeck-export","version":1,"exportedAt":"2026-01-01T00:00:00Z","cards":["""
                + """{"name":"A","barcodeValue":"5901234123457","createdAt":"2026-01-01T00:00:00Z"},"""
                + """{"name":"B","barcodeValue":"GMMNDR78E17Q","createdAt":"2026-01-01T00:00:00Z"}]}"""
        )
        val plan = CardTransfer.planImport(export, existingValues = setOf("5901234123457"))
        assertEquals(1, plan.toImport.size)
        assertEquals("GMMNDR78E17Q", plan.toImport[0].barcodeValue)
        assertEquals(1, plan.skipped)
    }

    @Test
    fun `import plan skips blank values`() {
        val export = CardTransfer.decode(
            """{"type":"barcodedeck-export","version":1,"exportedAt":"2026-01-01T00:00:00Z","cards":["""
                + """{"name":"Broken","barcodeValue":"   ","createdAt":"2026-01-01T00:00:00Z"}]}"""
        )
        val plan = CardTransfer.planImport(export, existingValues = emptySet())
        assertEquals(0, plan.toImport.size)
        assertEquals(1, plan.skipped)
    }
}
