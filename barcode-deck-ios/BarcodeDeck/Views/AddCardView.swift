import SwiftData
import SwiftUI

/// Form for adding a new card. Presented either blank (manual entry) or
/// prefilled with a scanned barcode value + symbology from the camera.
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var existingCards: [Card]

    @State private var name = ""
    @State private var cardDescription = ""
    @State private var barcodeValue: String
    /// The manually chosen type (`nil` = Auto-detect). Initialized to the
    /// scanned symbology when it is one of the selectable options.
    @State private var selectedType: String?
    private let scannedValue: String
    private let scannedSymbology: String?

    init(prefilledValue: String = "", prefilledSymbology: String? = nil) {
        _barcodeValue = State(initialValue: prefilledValue)
        _selectedType = State(
            initialValue: BarcodeValidation.manualTypeOptions.contains(prefilledSymbology)
                ? prefilledSymbology
                : nil
        )
        scannedValue = prefilledValue
        scannedSymbology = prefilledSymbology
    }

    /// Tracks focus of the barcode value field so its hints can be scrolled
    /// into view above the keyboard.
    @FocusState private var barcodeFieldFocused: Bool
    /// Scroll anchor for the barcode hints (footer of the Barcode section).
    private static let barcodeHintsID = "barcode-hints"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section("Card") {
                        TextField("Name", text: $name)
                        TextField("Description (optional)", text: $cardDescription, axis: .vertical)
                    }

                    Section {
                        Picker("Type", selection: $selectedType) {
                            Text("Auto-detect").tag(String?.none)
                            ForEach(
                                BarcodeValidation.manualTypeOptions.compactMap { $0 },
                                id: \.self
                            ) { type in
                                Text(type).tag(String?.some(type))
                            }
                        }
                        TextField("Barcode value", text: barcodeBinding)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(
                                selectedType == "Code 39" ? .characters : .never
                            )
                            .keyboardType(isGS1Type ? .numberPad : .default)
                            .autocorrectionDisabled()
                            .focused($barcodeFieldFocused)
                    } header: {
                        Text("Barcode")
                    } footer: {
                        barcodeFooter
                            .id(Self.barcodeHintsID)
                    }
                }
                .onChange(of: barcodeFieldFocused) { _, focused in
                    // When the value field gains focus, make sure the hints
                    // right below it end up above the keyboard too (the form
                    // only guarantees the field itself).
                    guard focused else { return }
                    withAnimation {
                        proxy.scrollTo(Self.barcodeHintsID, anchor: .bottom)
                    }
                }
            }
            .navigationTitle("New Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: selectedType) { _, newType in
                // Code 39 has no lowercase: bring existing input along.
                if newType == "Code 39" {
                    barcodeValue = barcodeValue.uppercased()
                }
            }
        }
    }

    // MARK: - Derived state

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String? {
        let trimmed = cardDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var trimmedBarcodeValue: String {
        barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isGS1Type: Bool {
        selectedType == "EAN-13" || selectedType == "UPC-A"
    }

    /// Uppercases input while Code 39 is selected (it has no lowercase).
    private var barcodeBinding: Binding<String> {
        Binding(
            get: { barcodeValue },
            set: { barcodeValue = selectedType == "Code 39" ? $0.uppercased() : $0 }
        )
    }

    private var typeError: String? {
        BarcodeValidation.manualTypeError(type: selectedType, value: trimmedBarcodeValue)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !trimmedBarcodeValue.isEmpty && typeError == nil
    }

    /// The symbology to persist:
    /// - the scanned one while the value is untouched and the type is Auto,
    /// - the explicitly chosen type,
    /// - otherwise the Auto-detect resolution of the typed value.
    private var effectiveSymbology: String? {
        if let scannedSymbology, trimmedBarcodeValue == scannedValue, selectedType == nil {
            return scannedSymbology
        }
        if let selectedType {
            return selectedType
        }
        return BarcodeValidation.resolveAutoSymbology(trimmedBarcodeValue)
    }

    private var duplicateCardName: String? {
        guard !trimmedBarcodeValue.isEmpty else { return nil }
        return existingCards.first { $0.displayBarcodeValue == trimmedBarcodeValue }?.displayName
    }

    private struct FooterMessage {
        let text: String
        let isError: Bool
    }

    @ViewBuilder
    private var barcodeFooter: some View {
        let messages = footerMessages
        if messages.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages, id: \.text) { message in
                    Text(message.text)
                        .foregroundStyle(message.isError ? Color.red : Color.secondary)
                }
            }
        }
    }

    private var footerMessages: [FooterMessage] {
        var messages: [FooterMessage] = []
        let value = trimmedBarcodeValue

        if let error = typeError {
            messages.append(FooterMessage(text: error, isError: true))
        } else if !value.isEmpty {
            if let scannedSymbology, value == scannedValue {
                messages.append(FooterMessage(text: "Scanned as \(scannedSymbology).", isError: false))
            } else if let selectedType {
                if selectedType == "EAN-13" && value.count < 13 {
                    messages.append(FooterMessage(text: "\(value.count)/13 digits", isError: false))
                } else if selectedType == "UPC-A" && value.count < 12 {
                    messages.append(FooterMessage(text: "\(value.count)/12 digits", isError: false))
                } else if (selectedType == "EAN-13" && value.count == 13)
                            || (selectedType == "UPC-A" && value.count == 12) {
                    messages.append(FooterMessage(
                        text: "Valid \(selectedType) check digit.", isError: false
                    ))
                } else if selectedType == "Code 39" {
                    messages.append(FooterMessage(
                        text: "Uppercase letters, digits, space and - . $ / + %.",
                        isError: false
                    ))
                } else if selectedType == "Code 128" {
                    messages.append(FooterMessage(
                        text: "Letters, digits and symbols (plain ASCII).",
                        isError: false
                    ))
                }
            } else {
                // Auto-detect: explain what the value resolves to.
                if let classified = BarcodeValidation.classify(value) {
                    messages.append(FooterMessage(
                        text: "Auto-detected: \(classified) (valid check digit).",
                        isError: false
                    ))
                } else if value.allSatisfy({ $0.isASCII && $0.isNumber }),
                          value.count == 13 || value.count == 12 || value.count == 8 {
                    messages.append(FooterMessage(
                        text: "Check digit doesn't match — double-check the digits. "
                            + "Auto will save it as Code 128.",
                        isError: true
                    ))
                } else if BarcodeValidation.isCode128Encodable(value) {
                    messages.append(FooterMessage(text: "Auto will save it as Code 128.", isError: false))
                } else {
                    messages.append(FooterMessage(
                        text: "Can't be encoded as a barcode — presentation will show it as text.",
                        isError: true
                    ))
                }
            }
        }

        if let duplicate = duplicateCardName {
            messages.append(FooterMessage(
                text: "Already saved as “\(duplicate)”. You can still save it.",
                isError: true
            ))
        }

        return messages
    }

    // MARK: - Actions

    private func save() {
        // Store the canonical EAN-13 form of UPC-A values so decks match
        // across platforms and imports de-duplicate (see BarcodeValidation).
        let (storedValue, storedSymbology) =
            BarcodeValidation.canonicalize(trimmedBarcodeValue, effectiveSymbology)
        let card = Card(
            name: trimmedName,
            cardDescription: trimmedDescription,
            barcodeValue: storedValue,
            symbology: storedSymbology
        )
        modelContext.insert(card)
        dismiss()
    }
}

#Preview {
    AddCardView()
        .modelContainer(for: Card.self, inMemory: true)
}

#Preview("Prefilled") {
    AddCardView(prefilledValue: "5901234123457", prefilledSymbology: "EAN-13")
        .modelContainer(for: Card.self, inMemory: true)
}
