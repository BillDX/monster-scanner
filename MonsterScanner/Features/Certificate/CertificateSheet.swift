import MonsterCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Preview of the Certificate of Monsterhood with a Share button. The PNG is
/// rendered only when Share is tapped and goes only to the system share sheet
/// (spec section 5). "Save Image" works through the add-only photo-library
/// permission (Bill approved it, DECISIONS.md D-026); the app never reads Photos.
struct CertificateSheet: View {
    let content: CertificateContent
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: CertificatePNG?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CertificateThumbnail(content: content)
                        .padding(.horizontal, 16)
                    Button("Share certificate") { share() }
                        .buttonStyle(NeonButtonStyle(filled: true))
                        .padding(.horizontal, 24)
                        .accessibilityHint("Opens the share sheet with an image of the certificate")
                    Text("Only you decide where it goes. The image has no location or camera data.")
                        .font(Theme.mono(.caption2))
                        .foregroundStyle(Theme.dimNeon)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.vertical, 20)
            }
            .background(Theme.background)
            .navigationTitle("Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.source])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func share() {
        SoundFX.shared.play(.stamp)
        guard let png = CertificateRenderer.pngData(for: content, scale: 2) else { return }
        shareItem = CertificatePNG(source: PNGActivitySource(png: png))
    }
}

private struct CertificatePNG: Identifiable {
    let id = UUID()
    let source: PNGActivitySource
}

/// Hands the share sheet the exact, metadata-free PNG bytes.
private final class PNGActivitySource: NSObject, UIActivityItemSource {
    private let png: Data
    private let preview: UIImage?

    init(png: Data) {
        self.png = png
        preview = UIImage(data: png)
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        preview ?? png
    }

    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        png
    }

    func activityViewController(_ controller: UIActivityViewController, dataTypeIdentifierForActivityType type: UIActivity.ActivityType?) -> String {
        UTType.png.identifier
    }

    func activityViewController(_ controller: UIActivityViewController, subjectForActivityType type: UIActivity.ActivityType?) -> String {
        "Certificate of Monsterhood"
    }

    func activityViewController(_ controller: UIActivityViewController, thumbnailImageForActivityType type: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        preview
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // Save Image uses NSPhotoLibraryAddUsageDescription (add-only, approved by Bill).
        controller.excludedActivityTypes = [.assignToContact, .addToReadingList]
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension ScanSession {
    /// Everything the certificate shows, from this scan.
    var certificateContent: CertificateContent? {
        guard let verdict, let dossier else { return nil }
        return CertificateContent(
            monster: verdict.monster,
            title: verdict.monster.verdictTitle,
            subspecies: subspecies,
            confidenceText: verdict.confidenceText,
            caseNumber: verdict.caseNumber,
            issuedOn: .now,
            fieldNote: observations.vibe.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? exhibits.first,
            recommendedAction: dossier.recommendedAction,
            trueAgeYears: verdict.trueAgeYears,
            photo: displayImage
        )
    }
}
