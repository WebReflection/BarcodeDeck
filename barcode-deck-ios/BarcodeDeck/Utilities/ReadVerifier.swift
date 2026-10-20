import Foundation

/// Accuracy gate for scanner reads: a capture is only confirmed once the
/// same (value, symbology) pair has been read `requiredReads` times in a
/// row.
///
/// Scanners occasionally misread large codes after a single pass;
/// requiring consecutive identical reads means a wrong save would need the
/// *same* mistake to repeat, which is very unlikely — a different read
/// resets the candidate to the new value, and frames without any read
/// change nothing. Accuracy is worth the extra ~second: detection itself
/// is fast, it is the single-pass correctness that is not guaranteed.
struct ReadVerifier {
    let requiredReads: Int

    private(set) var value: String?
    private(set) var symbology: String?
    private(set) var count = 0

    /// Registers a read; returns true when the capture is confirmed.
    mutating func onRead(value: String, symbology: String?) -> Bool {
        if value == self.value && symbology == self.symbology {
            count += 1
        } else {
            self.value = value
            self.symbology = symbology
            count = 1
        }
        return count >= requiredReads
    }
}
