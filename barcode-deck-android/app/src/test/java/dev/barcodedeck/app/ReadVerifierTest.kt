package dev.barcodedeck.app

import dev.barcodedeck.app.scanner.ReadVerifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadVerifierTest {

    @Test fun `confirms after required consecutive identical reads`() {
        val verifier = ReadVerifier(3)
        assertFalse(verifier.onRead("123", "ITF"))
        assertFalse(verifier.onRead("123", "ITF"))
        assertTrue(verifier.onRead("123", "ITF"))
    }

    @Test fun `different read resets the streak to the new value`() {
        val verifier = ReadVerifier(3)
        assertFalse(verifier.onRead("123", "ITF"))
        assertFalse(verifier.onRead("123", "ITF"))
        assertFalse(verifier.onRead("456", "ITF"))  // single-pass misread
        assertFalse(verifier.onRead("456", "ITF"))
        assertTrue(verifier.onRead("456", "ITF"))
    }

    @Test fun `symbology is part of the read identity`() {
        val verifier = ReadVerifier(2)
        assertFalse(verifier.onRead("123", null))
        assertFalse(verifier.onRead("123", "ITF"))
        assertTrue(verifier.onRead("123", "ITF"))
    }

    @Test fun `count tracks the current streak`() {
        val verifier = ReadVerifier(3)
        verifier.onRead("1", null)
        assertEquals(1, verifier.count)
        verifier.onRead("1", null)
        assertEquals(2, verifier.count)
        verifier.onRead("2", null)
        assertEquals(1, verifier.count)
    }
}
