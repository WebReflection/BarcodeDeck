import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Home screen: the minimal TODO-list-like catalog of saved cards.
///
/// Flow: "+" opens the scanner; a captured barcode (or "Type it in")
/// opens the add form, prefilled when scanned. Cancel discards everything.
struct CardListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Card.createdAt, order: .reverse)
    private var cards: [Card]

    /// Local render order: follows the store. Reorders are written through
    /// to the store immediately (see moveCards), so it always matches it.
    @State private var orderedCards: [Card] = []
    /// Edit mode: rows grow reorder handles and dragging reorders via onMove.
    /// Entered with the reorder icon (line.3.horizontal), left with the
    /// checkmark — the mode only reorders, so no misleading "Edit" text.
    @State private var editMode: EditMode = .inactive

    /// In-memory snapshot of the last deleted card, undoable for 5 seconds.
    /// Deletion itself is a clear removal from the store — the snapshot is
    /// the only copy, and a new deletion (rage action) cancels the previous
    /// undo, sending that card forever.
    @State private var pendingUndo: CardSnapshot?
    @State private var undoTask: Task<Void, Never>?

    @State private var showingScanner = false
    @State private var pendingAdd: AddCardContext?
    @State private var addContext: AddCardContext?
    @State private var presentedCard: Card?
    @State private var showingImporter = false
    @State private var importSummary: CardTransfer.ImportSummary?
    @State private var importError: String?
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView(
                        "No cards yet",
                        systemImage: "barcode",
                        description: Text("Tap + to scan your first card.")
                    )
                } else {
                    cardList
                }
            }
            .navigationTitle("Barcode Deck")
            .safeAreaInset(edge: .bottom) {
                if let snapshot = pendingUndo {
                    undoBanner(snapshot)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if editMode == .active {
                            // Every move was already persisted; just exit.
                            withAnimation { editMode = .inactive }
                        } else {
                            withAnimation { editMode = .active }
                        }
                    } label: {
                        // Icon toggle instead of "Edit"/"Done" text: the mode
                        // reorders cards only, and "Edit" suggests per-item
                        // editing (Android reorders via long-press + drag).
                        Image(systemName: editMode == .active
                            ? "checkmark"
                            : "line.3.horizontal")
                    }
                    .accessibilityLabel(editMode == .active
                        ? "Done reordering"
                        : "Reorder cards")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        #if DEBUG
                        // Test hook: skip the scanner (no camera on the
                        // Simulator) and open the manual form directly.
                        if ProcessInfo.processInfo.arguments.contains("--debug-skip-scanner") {
                            addContext = .manual
                            return
                        }
                        #endif
                        showingScanner = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add card")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            exportCards()
                        } label: {
                            Label("Export JSON…", systemImage: "square.and.arrow.up")
                        }
                        .disabled(cards.isEmpty)

                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import JSON…", systemImage: "square.and.arrow.down")
                        }

                        Divider()

                        Button {
                            showingAbout = true
                        } label: {
                            Label("About Barcode Deck", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More options")
                }
            }
            .fullScreenCover(isPresented: $showingScanner, onDismiss: promotePendingAdd) {
                ScanSheet(
                    onCapture: { value, symbology in
                        pendingAdd = .scanned(value: value, symbology: symbology)
                        showingScanner = false
                    },
                    onManualEntry: {
                        pendingAdd = .manual
                        showingScanner = false
                    },
                    onCancel: {
                        pendingAdd = nil
                        showingScanner = false
                    }
                )
            }
            .sheet(item: $addContext) { context in
                switch context {
                case .scanned(let value, let symbology):
                    AddCardView(prefilledValue: value, prefilledSymbology: symbology)
                case .manual:
                    AddCardView()
                }
            }
            .fullScreenCover(item: $presentedCard, onDismiss: restoreOrientation) { card in
                PresentationView(card: card)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .alert(
                "Import complete",
                isPresented: Binding(
                    get: { importSummary != nil },
                    set: { if !$0 { importSummary = nil } }
                ),
                presenting: importSummary
            ) { _ in
                Button("OK") { importSummary = nil }
            } message: { summary in
                Text(summary.message)
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            #if DEBUG
            .onAppear {
                // Debug hook: --debug-reset-store wipes all cards on launch
                // (UI tests start from a clean store).
                if ProcessInfo.processInfo.arguments.contains("--debug-reset-store") {
                    for card in cards { modelContext.delete(card) }
                    try? modelContext.save()
                }
                // Debug hook: --debug-show-add opens the manual add form on
                // launch (skips the scanner, whose camera is unavailable on
                // the Simulator).
                if ProcessInfo.processInfo.arguments.contains("--debug-show-add") {
                    addContext = .manual
                }
                // Debug hook: --debug-show-scanner opens the scan sheet on launch
                // (useful for Simulator where there's no camera).
                if ProcessInfo.processInfo.arguments.contains("--debug-show-scanner") {
                    showingScanner = true
                }
                // Debug hook: --debug-present-demo shows presentation mode for a
                // hardcoded demo card, without persisting anything.
                // --debug-present-ean does the same with an EAN-13 card.
                if ProcessInfo.processInfo.arguments.contains("--debug-present-demo") {
                    presentedCard = Card(
                        name: "Green Grocery",
                        cardDescription: "Loyalty — ask for the weekend sticker",
                        barcodeValue: "A123456789",
                        symbology: "Code 128"
                    )
                }
                if ProcessInfo.processInfo.arguments.contains("--debug-present-ean") {
                    presentedCard = Card(
                        name: "Corner Pharmacy",
                        cardDescription: "Member n° 42",
                        barcodeValue: "4006381333931",
                        symbology: "EAN-13"
                    )
                }
                if ProcessInfo.processInfo.arguments.contains("--debug-present-cf") {
                    presentedCard = Card(
                        name: "Codice Fiscale",
                        cardDescription: nil,
                        barcodeValue: "GMMNDR78E17A271Q",
                        symbology: "Code 39"
                    )
                }
            }
            #endif
        }
    }

    private var cardList: some View {
        List {
            ForEach(orderedCards) { card in
                Button {
                    if editMode == .inactive {
                        presentedCard = card
                    }
                } label: {
                    CardRowView(card: card)
                        .contentShape(Rectangle())
                }
                // Plain style: whole row tappable, no default chrome —
                // equivalent to Android's row click.
                .buttonStyle(.plain)
            }
            .onMove(perform: moveCards)
            .onDelete(perform: deleteCards)
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .onAppear { orderedCards = cards }
        .onChange(of: cards) { _, newCards in
            guard editMode == .inactive else { return }
            orderedCards = newCards
        }
    }

    /// Reorder callback from the List's native move machinery. The visual
    /// order updates live and every step is written through immediately, so
    /// the order survives the app being closed at any moment.
    private func moveCards(from source: IndexSet, to destination: Int) {
        AppDelegate.log.debug("moveCards \(source) → \(destination)")
        orderedCards.move(fromOffsets: source, toOffset: destination)
        persistOrder(orderedCards)
    }

    /// Banner shown for the 5-second undo window after a deletion.
    @ViewBuilder
    private func undoBanner(_ snapshot: CardSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Deleted \"\(snapshot.name)\"")
                    .font(.subheadline.weight(.medium))
                Text("Gone forever in 5 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Undo") {
                undoPendingDeletion()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Trims an optional string, collapsing empty results to nil — used for
    /// optional card fields coming from imported JSON.
    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Persists the manual order without any schema change: position 0 (top)
    /// gets the newest timestamp, descending in 1-second steps down the list.
    /// The display order (createdAt DESC) then matches the list, and future
    /// cards (createdAt = now) land on top automatically.
    private func persistOrder(_ ordered: [Card]) {
        AppDelegate.log.debug("persistOrder \(ordered.map(\.displayName), privacy: .public)")
        CardOrder.apply(ordered, context: modelContext)
    }

    private func deleteCards(at offsets: IndexSet) {
        AppDelegate.log.debug("deleteCards at \(offsets)")
        guard let firstIndex = offsets.first else { return }
        let snapshot = CardSnapshot(from: orderedCards[firstIndex])
        for index in offsets {
            // Clear removal: the row leaves the store immediately. The undo
            // window below works on the in-memory snapshot only.
            modelContext.delete(orderedCards[index])
        }
        try? modelContext.save()

        // Rage rule: a new deletion cancels the previous undo — that card
        // goes forever. Otherwise the snapshot lives exactly 5 seconds.
        undoTask?.cancel()
        withAnimation { pendingUndo = snapshot }
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation { pendingUndo = nil }
        }
    }

    private func undoPendingDeletion() {
        guard let snapshot = pendingUndo else { return }
        undoTask?.cancel()
        withAnimation { pendingUndo = nil }
        modelContext.insert(snapshot.asCard)
        try? modelContext.save()
    }

    /// After the scanner cover finishes dismissing, open the add form
    /// (prefilled for a capture, blank for manual entry). Cancel leaves
    /// `pendingAdd` nil and nothing is presented.
    private func promotePendingAdd() {
        guard let pending = pendingAdd else { return }
        pendingAdd = nil
        addContext = pending
    }

    /// Runs after presentation mode has fully dismissed (so the geometry
    /// request can't be dropped mid-transition): unlock rotation and rotate
    /// back to the orientation the user had before entering.
    private func restoreOrientation() {
        AppDelegate.log.info("restoreOrientation (onDismiss) fired, restoring \(String(describing: AppDelegate.restoreOrientation), privacy: .public)")
        AppDelegate.orientationLock = .all
        AppDelegate.rotate(to: AppDelegate.restoreOrientation)
    }

    // MARK: - Export / Import

    private func exportCards() {
        do {
            let export = CardTransfer.makeExport(from: cards)
            let data = try CardTransfer.encode(export)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(CardTransfer.exportFileName())
            try data.write(to: url)
            presentExportSheet(url)
        } catch {
            importError = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Presents the system share sheet imperatively from the topmost view
    /// controller. (Hosting a UIActivityViewController via a
    /// UIViewControllerRepresentable inside a sheet rendered a blank,
    /// un-dismissable screen on recent iOS versions.)
    private func presentExportSheet(_ url: URL) {
        // Let the menu dismissal finish first: UIKit refuses a presentation
        // while another one is in flight.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let controller = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )
            guard var top = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.keyWindow?.rootViewController else { return }
            while let presented = top.presentedViewController {
                top = presented
            }
            top.present(controller, animated: true)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importCards(from: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func importCards(from url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let export = try CardTransfer.decodeExport(from: data)
            let existingValues = Set(cards.map(\.displayBarcodeValue))
            let plan = CardTransfer.planImport(export, existingValues: existingValues)

            for cardData in plan.toImport {
                // Imported values are trimmed like manually typed ones; no
                // supported symbology here carries meaningful leading/trailing
                // whitespace.
                modelContext.insert(Card(
                    name: cardData.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    cardDescription: trimmed(cardData.description),
                    barcodeValue: cardData.barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines),
                    symbology: trimmed(cardData.symbology),
                    createdAt: cardData.createdAt
                ))
            }

            importSummary = CardTransfer.ImportSummary(
                imported: plan.toImport.count,
                skipped: plan.skipped
            )
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// What the add form should be prefilled with.
enum AddCardContext: Identifiable {
    case scanned(value: String, symbology: String?)
    case manual

    var id: String {
        switch self {
        case .scanned(let value, _): return "scanned-\(value)"
        case .manual: return "manual"
        }
    }
}

/// Plain-value copy of a deleted card: the only thing the 5-second undo
/// window keeps (the store itself is cleanly updated on deletion).
private struct CardSnapshot {
    let name: String
    let cardDescription: String?
    let barcodeValue: String
    let symbology: String?
    let createdAt: Date

    init(from card: Card) {
        name = card.name
        cardDescription = card.cardDescription
        barcodeValue = card.barcodeValue
        symbology = card.symbology
        createdAt = card.createdAt
    }

    var asCard: Card {
        Card(
            name: name,
            cardDescription: cardDescription,
            barcodeValue: barcodeValue,
            symbology: symbology,
            createdAt: createdAt
        )
    }
}

#Preview {
    CardListView()
        .modelContainer(for: Card.self, inMemory: true)
}
