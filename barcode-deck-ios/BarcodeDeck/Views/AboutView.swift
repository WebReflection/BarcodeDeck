import SwiftUI

/// The "About" sheet: essential info only, reached from the toolbar menu
/// so it never disturbs the main flow. Points to the project's repository
/// for contributions, feedback and appreciation — no contact e-mail.
enum About {
    static let projectURL = URL(string: "https://github.com/WebReflection/BarcodeDeck")!
    static let issuesURL = URL(string: "https://github.com/WebReflection/BarcodeDeck/issues")!
    static let authorURL = URL(string: "https://github.com/WebReflection")!
    static let licenseName = "MIT License"

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        default: return ""
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Barcode Deck \(About.version)")
                    .font(.headline)

                Text(
                    "One card less in your wallet. Free, open source and " +
                    "offline — your cards never leave this device, and " +
                    "there is no account, analytics or tracking."
                )

                Text("The camera is used only to look at barcodes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Link("Source code & contributions", destination: About.projectURL)
                    Link("Feedback & issues", destination: About.issuesURL)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Link("by Andrea Giammarchi — @webreflection", destination: About.authorURL)
                    .font(.footnote)

                Text("Released under the \(About.licenseName).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    AboutView()
}
