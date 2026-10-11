import Foundation
import SwiftData

/// Order persistence for the card deck: the visual order is stored by
/// rewriting each card's `createdAt` (the list's sort key) — no schema
/// changes, no extra fields.
enum CardOrder {

    /// Persists `ordered` (top first) by assigning descending sort keys:
    /// position 0 gets `base`, the rest step down by 1 second. The display
    /// order (createdAt DESC) then matches `ordered`, and future cards
    /// (createdAt = now) land on top automatically.
    static func apply(_ ordered: [Card], context: ModelContext, base: Date = .now) {
        for (index, card) in ordered.enumerated() {
            card.createdAt = base.addingTimeInterval(-Double(index))
        }
        try? context.save()
    }

    /// The sort keys `apply` would write, exposed for testing.
    static func timestamps(count: Int, base: Date) -> [Date] {
        (0..<count).map { base.addingTimeInterval(-Double($0)) }
    }
}
