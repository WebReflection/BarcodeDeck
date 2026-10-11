import SwiftUI

/// A single row in the card list: name, optional description, barcode value.
struct CardRowView: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.displayName)
                .font(.headline)
                .lineLimit(1)

            if let description = card.displayDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if let symbology = card.symbology {
                    Text(symbology)
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
                Text(card.displayBarcodeValue)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        // Expand to the full row width so the whole line is tappable
        // (the VStack would otherwise hug the text content), matching
        // Android's full-width row click.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

#Preview {
    List {
        CardRowView(
            card: Card(
                name: "Green Grocery",
                cardDescription: "Membership card",
                barcodeValue: "5901234123457",
                symbology: "EAN-13"
            )
        )
        CardRowView(
            card: Card(
                name: "City Library",
                barcodeValue: "A123456789"
            )
        )
    }
    .listStyle(.plain)
}
