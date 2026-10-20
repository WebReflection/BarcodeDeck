package dev.barcodedeck.app.scanner

/**
 * Accuracy gate for scanner reads: a capture is only confirmed once the
 * same (value, symbology) pair has been read [requiredReads] times in a
 * row.
 *
 * Scanners occasionally misread large codes after a single pass; requiring
 * consecutive identical reads means a wrong save would need the *same*
 * mistake to repeat, which is very unlikely — a different read resets the
 * candidate to the new value, and frames without any read change nothing.
 * Accuracy is worth the extra ~fraction of a second: detection itself is
 * fast, it is the single-pass correctness that is not guaranteed.
 */
class ReadVerifier(private val requiredReads: Int) {
    var value: String? = null
        private set
    var symbology: String? = null
        private set
    var count: Int = 0
        private set

    /** Registers a read; returns true when the capture is confirmed. */
    fun onRead(value: String, symbology: String?): Boolean {
        if (value == this.value && symbology == this.symbology) {
            count++
        } else {
            this.value = value
            this.symbology = symbology
            count = 1
        }
        return count >= requiredReads
    }
}
