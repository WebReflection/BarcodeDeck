import Foundation
import SwiftData
import Testing
@testable import BarcodeDeck

/// Persistence of the card deck order: reordering rewrites the createdAt
/// sort keys (no schema changes), and a fresh fetch must return the new
/// order. This is the logic behind the drag-to-reorder UX.
@Suite struct CardOrderTests {

    @Test func reorderedDeckIsPersistedAndRefetchedInOrder() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Card.self, configurations: config)
        let context = ModelContext(container)

        // Seed: B created first, A second — A displays on top (DESC).
        let b = Card(name: "B", barcodeValue: "2", createdAt: Date.now)
        let a = Card(name: "A", barcodeValue: "1", createdAt: Date.now.addingTimeInterval(1))
        context.insert(b)
        context.insert(a)
        try context.save()

        let before = try context.fetch(
            FetchDescriptor<Card>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        ).map(\.name)
        #expect(before == ["A", "B"])

        // The user drags B above A: persist [B, A].
        CardOrder.apply([b, a], context: context, base: .now)

        let after = try context.fetch(
            FetchDescriptor<Card>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        ).map(\.name)
        #expect(after == ["B", "A"])

        // B (now on top) must be newer than A: future cards created with
        // createdAt = now land on top automatically.
        #expect(b.createdAt > a.createdAt)
    }

    @Test func timestampsAreStrictlyDescending() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let stamps = CardOrder.timestamps(count: 5, base: base)
        #expect(stamps.count == 5)
        for (older, newer) in zip(stamps.dropFirst(), stamps) {
            #expect(newer > older)
        }
        #expect(stamps.first == base)
    }

    @Test func singleCardDeckGetsBaseTimestamp() {
        let base = Date(timeIntervalSince1970: 2_000_000)
        let stamps = CardOrder.timestamps(count: 1, base: base)
        #expect(stamps == [base])
    }
}
