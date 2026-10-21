import CoreTransferable
import ImageIO
import MonsterCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// The shareable "Certificate of Monsterhood".
//
// Privacy: the image only exists after the player taps Share. It is rendered
// in memory with ImageRenderer, encoded to a PNG that holds nothing but pixels
// (no EXIF, no location: see MetadataFreePNG), handed to the system share
// sheet and never written to disk by us.

/// Everything printed on the certificate.
nonisolated struct CertificateContent: Sendable {
    var monster: Monster
    /// e.g. "VAMPIRE" or "CERTIFIED HUMAN… for now". Text after "…" is printed smaller.
    var title: String
    /// e.g. "Brunch Bat".
    var subspecies: String?
    /// "87.3%"
    var confidenceText: String
    /// "K9-4821"
    var caseNumber: String
    var issuedOn: Date
    /// One silly line, e.g. "A whimsical, coffee-sipping adventurer on a magical journey."
    var fieldNote: String?
    /// e.g. "Offer garlic bread and see what happens."
    var recommendedAction: String
    /// The joke "true age", e.g. 412.
    var trueAgeYears: Int
    /// The (consenting) subject's photo.
    var photo: UIImage?
}

// MARK: - The artwork

/// The certificate artwork, laid out for a fixed 1080 x 1350 pt canvas (portrait, Instagram-friendly).
struct CertificateCard: View {
    let content: CertificateContent

    static let size = CGSize(width: 1080, height: 1350)

    private var isHuman: Bool { content.monster == .human }
    private var flavor: CertificateFlavor { CertificateFlavor(content.monster) }

    var body: some View {
        ZStack {
            TerminalBezel(caseNumber: content.caseNumber)
                .frame(width: Self.size.width, height: Self.size.height)
            parchment
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Layout

    private var parchment: some View {
        ZStack {
            PaperTexture()
            GuillocheRosette(petals: 18, layers: 9, depth: 0.22)
                .stroke(CertificateInk.security.opacity(0.07), lineWidth: 1.2)
                .frame(width: 640, height: 640)
                .offset(y: 70)
                .accessibilityHidden(true)
            GuillocheFrame()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                titleBlock
                Spacer(minLength: 8)
                certifyLine
                Spacer(minLength: 10)
                // The verdict keeps its size; long notes shrink first.
                reveal.layoutPriority(1)
                Spacer(minLength: 12)
                readings
                Spacer(minLength: 12)
                notes
                Spacer(minLength: 10)
                signatures
                Spacer(minLength: 6)
                footer
            }
            .padding(.horizontal, 62)
            .padding(.top, 60)
            .padding(.bottom, 56)
        }
        // Fixed paper size: if text ever runs long it is clipped at the
        // bottom of the paper instead of pushing the layout off the canvas.
        .frame(width: Self.size.width - 52, height: Self.size.height - 80, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(CertificateInk.paper)
                .shadow(color: Theme.neon.opacity(0.45), radius: 12)
        )
    }

    private var header: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .top) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "FORM K9-13 (REV. FULL MOON)")
                        Text(verbatim: "FILE UNDER: \(isHuman ? "BORING" : content.monster.rawValue.uppercased())")
                        Text(verbatim: "COPIES: 1 (ONE). DO NOT FEED.")
                    }
                    .font(CertificateInk.typewriter(14))
                    .foregroundStyle(CertificateInk.fadedInk)
                    Spacer()
                }
                BureauEmblem(size: 100)
            }
            .overlay(alignment: .topTrailing) {
                RubberStamp(text: isHuman ? "DECLASSIFIED" : "CLASSIFIED", size: 34, angle: 11)
                    .offset(x: 6, y: 18)
            }
            Text(verbatim: "BUREAU OF SECRET MONSTER AFFAIRS")
                .font(CertificateInk.copperplate(36))
                .tracking(1.5)
                .foregroundStyle(CertificateInk.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: "DEPARTMENT OF UNEXPLAINED PHENOMENA · FIELD SCANNER DIVISION")
                .font(CertificateInk.copperplate(16, bold: false))
                .tracking(1)
                .foregroundStyle(CertificateInk.fadedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var titleBlock: some View {
        VStack(spacing: -16) {
            Text(verbatim: "CERTIFICATE")
                .font(CertificateInk.didot(72))
                .tracking(6)
                .foregroundStyle(CertificateInk.ink)
            Text(verbatim: isHuman ? "of Disappointing Humanity" : "of Monsterhood")
                .font(CertificateInk.script(isHuman ? 48 : 56))
                .foregroundStyle(CertificateInk.stampRed)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var certifyLine: some View {
        VStack(spacing: 10) {
            ornament
            Text(verbatim: isHuman
                ? "This is to certify that, despite a thorough* and frankly enthusiastic scan, the bearer of this document has been found to be, regrettably, a"
                : "This is to certify that the bearer of this document has been scientifically* identified as \(article)")
                .font(CertificateInk.serifItalic(isHuman ? 26 : 27))
                .foregroundStyle(CertificateInk.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                // Narrower measure so the monster sentence breaks into two even lines.
                .padding(.horizontal, isHuman ? 0 : 70)
        }
    }

    private var ornament: some View {
        HStack(spacing: 14) {
            Rectangle().frame(height: 1.5)
            Text(verbatim: "✦ ✦ ✦").font(CertificateInk.copperplate(16))
            Rectangle().frame(height: 1.5)
        }
        .foregroundStyle(CertificateInk.security)
        .padding(.horizontal, 120)
        .accessibilityHidden(true)
    }

    private var reveal: some View {
        HStack(alignment: .center, spacing: 24) {
            PolaroidPhoto(photo: content.photo)
                .padding(.leading, 6)
            VStack(spacing: 4) {
                Text(verbatim: content.monster.emoji)
                    .font(.system(size: 116))
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 5)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) {
                        RubberStamp(text: flavor.stamp, size: isHuman ? 24 : 27, angle: 9)
                            .offset(x: 4, y: 26)
                    }
                Text(verbatim: titleParts.main)
                    .font(CertificateInk.stamp(titleParts.main.count > 9 ? 80 : 104))
                    .tracking(3)
                    .foregroundStyle(isHuman ? CertificateInk.ink : CertificateInk.stampRed)
                    .shadow(color: CertificateInk.ink.opacity(0.25), radius: 0, x: 2, y: 2)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    // Avenir's generous built-in leading wastes vertical space.
                    .padding(.vertical, -12)
                if let tail = titleParts.tail {
                    Text(verbatim: tail)
                        .font(CertificateInk.script(44))
                        .foregroundStyle(CertificateInk.stampRed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, -10)
                }
                Text(verbatim: "Subspecies: \(subspecies)")
                    .font(CertificateInk.serifItalic(30))
                    .foregroundStyle(CertificateInk.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var readings: some View {
        HStack(spacing: 14) {
            field("CONFIDENCE", content.confidenceText)
            field("TRUE AGE", trueAge)
            field("CLEARANCE", flavor.clearance)
            field("CASE No.", content.caseNumber)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: label)
                .font(CertificateInk.copperplate(16))
                .tracking(1)
                .foregroundStyle(CertificateInk.fadedInk)
            Text(verbatim: value)
                .font(CertificateInk.typewriter(30, bold: true))
                .foregroundStyle(CertificateInk.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(height: 38)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(CertificateInk.paperEdge.opacity(0.16))
        .overlay(Rectangle().stroke(CertificateInk.ink.opacity(0.8), lineWidth: 1.5))
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            note("FIELD NOTE", fieldNote)
            note("RECOMMENDED ACTION", content.recommendedAction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ label: String, _ value: String) -> some View {
        var line = AttributedString("\(label): ")
        line.font = CertificateInk.copperplate(21)
        line.foregroundColor = CertificateInk.stampRed
        var text = AttributedString(value)
        text.font = CertificateInk.typewriter(25)
        text.foregroundColor = CertificateInk.ink
        line.append(text)
        return Text(line)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .lineSpacing(2)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(CertificateInk.ink.opacity(0.25))
                    .frame(height: 1)
            }
    }

    private var signatures: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Agent K-9")
                    .font(CertificateInk.script(52))
                    .foregroundStyle(CertificateInk.penBlue)
                    .fixedSize()
                    .rotationEffect(.degrees(-4))
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        PawPrint()
                            .fill(CertificateInk.penBlue.opacity(0.85))
                            .frame(width: 50, height: 46)
                            .rotationEffect(.degrees(18))
                            .padding(.trailing, 14)
                    }
                Rectangle()
                    .fill(CertificateInk.ink)
                    .frame(width: 350, height: 1.5)
                Text(verbatim: "AGENT K-9, FIELD SCANNER DIVISION")
                    .font(CertificateInk.copperplate(15))
                    .foregroundStyle(CertificateInk.ink)
                Text(verbatim: "Very Good Boy · Senior Sniffer, Grade III")
                    .font(CertificateInk.serifItalic(16))
                    .foregroundStyle(CertificateInk.fadedInk)
            }
            .frame(width: 350, alignment: .leading)

            VStack(spacing: 3) {
                Text(verbatim: "ISSUED ON")
                    .font(CertificateInk.copperplate(15))
                    .foregroundStyle(CertificateInk.fadedInk)
                Text(verbatim: issuedDate)
                    .font(CertificateInk.typewriter(26, bold: true))
                    .foregroundStyle(CertificateInk.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: moonLine)
                    .font(CertificateInk.serifItalic(18))
                    .foregroundStyle(CertificateInk.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: "Valid until \(flavor.validUntil).")
                    .font(CertificateInk.serifItalic(18))
                    .foregroundStyle(CertificateInk.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            WaxSeal(motto: flavor.sealMotto, size: 150)
                .frame(width: 150, height: 130, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        Text(verbatim: "*Not science. Readings may be wildly inaccurate. Issued for fun. Not valid in Transylvania.")
            .font(.custom("Baskerville-Italic", fixedSize: 17))
            .foregroundStyle(CertificateInk.fadedInk)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: 660)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Text helpers

    /// "VAMPIRE" → ("VAMPIRE", nil); "CERTIFIED HUMAN… for now" → ("CERTIFIED HUMAN", "…for now").
    private var titleParts: (main: String, tail: String?) {
        let pieces = content.title.split(separator: "…", maxSplits: 1, omittingEmptySubsequences: false)
        let main = pieces[0].trimmingCharacters(in: .whitespaces)
        guard pieces.count == 2, !main.isEmpty else { return (content.title, nil) }
        let rest = pieces[1].trimmingCharacters(in: .whitespaces)
        return (main, rest.isEmpty ? nil : "…\(rest)")
    }

    private var article: String {
        let first = content.title.trimmingCharacters(in: .whitespaces).uppercased().first
        return first.map { "AEIOU".contains($0) } == true ? "an" : "a"
    }

    private var subspecies: String {
        if let subspecies = content.subspecies?.trimmingCharacters(in: .whitespaces), !subspecies.isEmpty {
            return subspecies
        }
        return isHuman ? "Homo sapiens (regular)" : "[REDACTED]"
    }

    private var fieldNote: String {
        if let note = content.fieldNote?.trimmingCharacters(in: .whitespaces), !note.isEmpty { return note }
        return "None filed. Agent K-9 was distracted by a squirrel."
    }

    private var trueAge: String {
        "\(content.trueAgeYears.formatted()) \(content.trueAgeYears == 1 ? "YEAR" : "YEARS")"
    }

    private var issuedDate: String {
        content.issuedOn.formatted(.dateTime.day().month(.abbreviated).year()).uppercased()
    }

    private var moonLine: String {
        let phase = MoonPhase.name(at: content.issuedOn).lowercased()
        let moon = phase.hasSuffix("moon") ? phase : "\(phase) moon"
        return "under a \(moon) \(moonEmoji(phase))"
    }

    private func moonEmoji(_ phase: String) -> String {
        switch phase {
        case "new moon": "🌑"
        case "waxing crescent": "🌒"
        case "first quarter": "🌓"
        case "waxing gibbous": "🌔"
        case "full moon": "🌕"
        case "waning gibbous": "🌖"
        case "last quarter": "🌗"
        default: "🌘"
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            isHuman ? "Certificate of Disappointing Humanity" : "Certificate of Monsterhood",
            "from the Bureau of Secret Monster Affairs.",
            "Verdict: \(content.title).",
            "Subspecies: \(subspecies).",
            "Confidence \(content.confidenceText). True age \(trueAge). Case \(content.caseNumber).",
            "Field note: \(fieldNote)",
            "Recommended action: \(content.recommendedAction)",
            "Signed, Agent K-9.",
        ]
        if content.photo != nil { parts.insert("Includes the subject's photo.", at: 3) }
        return parts.joined(separator: " ")
    }
}

/// The certificate scaled down to fit the available width, for showing on screen.
struct CertificateThumbnail: View {
    let content: CertificateContent

    var body: some View {
        Color.clear
            .aspectRatio(CertificateCard.size.width / CertificateCard.size.height, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    CertificateCard(content: content)
                        .scaleEffect(proxy.size.width / CertificateCard.size.width, anchor: .topLeading)
                }
            }
            .clipped()
    }
}

// MARK: - Rendering

/// Renders the card to PNG data (no metadata) at the given scale.
enum CertificateRenderer {
    @MainActor static func pngData(for content: CertificateContent, scale: CGFloat = 1) -> Data? {
        let renderer = ImageRenderer(content: CertificateCard(content: content))
        renderer.proposedSize = ProposedViewSize(CertificateCard.size)
        renderer.scale = scale
        renderer.isOpaque = true
        // The very first render after a cold launch can come back empty, so
        // try once more before giving up.
        guard let image = renderer.cgImage ?? renderer.cgImage else { return nil }
        return MetadataFreePNG.encode(image)
    }
}

/// PNG encoding that keeps only the pixels. Both `UIImage.pngData()` and a
/// bare ImageIO destination add an `eXIf` chunk (orientation, resolution,
/// dimensions), so the encoded file is rebuilt from an allow-list of chunks:
/// no EXIF, GPS, text, timestamps or private chunks can ride along.
nonisolated enum MetadataFreePNG {
    /// Chunks that describe pixels and colour. Everything else is dropped.
    private static let allowedChunks: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND", "sRGB", "iCCP", "gAMA", "cHRM"]
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func encode(_ image: CGImage) -> Data? {
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return stripMetadata(encoded as Data)
    }

    /// Copies only allow-listed chunks. Returns nil for anything that isn't a well-formed PNG.
    static func stripMetadata(_ png: Data) -> Data? {
        let bytes = [UInt8](png)
        guard bytes.count > signature.count, Array(bytes.prefix(signature.count)) == signature else { return nil }
        var output = Data(signature)
        var offset = signature.count
        while offset + 12 <= bytes.count {
            let length = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            let end = offset + 12 + length  // length + type + data + CRC
            guard end <= bytes.count else { return nil }
            let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
            if allowedChunks.contains(type) {
                output.append(contentsOf: bytes[offset..<end])
            }
            offset = end
            if type == "IEND" { return output }
        }
        return nil
    }
}

/// Lazily rendered PNG for the share sheet: nothing is drawn until the
/// system asks for the data, which only happens after the player taps Share.
nonisolated struct CertificateShareItem: Transferable, Sendable {
    let content: CertificateContent
    /// 2x gives a crisp 2160 x 2700 image.
    var scale: CGFloat = 2

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await item.renderPNG()
        }
        .suggestedFileName("Certificate-of-Monsterhood.png")
    }

    func renderPNG() async throws -> Data {
        guard let data = await CertificateRenderer.pngData(for: content, scale: scale) else {
            throw CertificateRenderError()
        }
        return data
    }
}

nonisolated struct CertificateRenderError: Error {}

/// A button that, when tapped, renders the certificate and presents the share sheet.
struct ShareCertificateButton: View {
    let content: CertificateContent

    var body: some View {
        ShareLink(
            item: CertificateShareItem(content: content),
            preview: SharePreview(
                content.monster == .human ? "Certificate of Disappointing Humanity" : "Certificate of Monsterhood",
                image: CertificateShareItem(content: content, scale: 0.3)
            )
        ) {
            Label("Share Certificate", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(NeonButtonStyle())
        .accessibilityHint("Creates the certificate image and opens the share sheet")
    }
}

// MARK: - Previews

#if DEBUG
extension CertificateContent {
    static let previewVampire = CertificateContent(
        monster: .vampire,
        title: Monster.vampire.verdictTitle,
        subspecies: "Brunch Bat",
        confidenceText: "87.3%",
        caseNumber: "K9-4821",
        issuedOn: .now,
        fieldNote: "A whimsical, coffee-sipping adventurer on a magical journey.",
        recommendedAction: "Offer garlic bread and see what happens.",
        trueAgeYears: 412,
        photo: .certificatePlaceholder
    )

    static let previewHuman = CertificateContent(
        monster: .human,
        title: Monster.human.verdictTitle,
        subspecies: nil,
        confidenceText: "51.2%",
        caseNumber: "K9-0007",
        issuedOn: .now,
        fieldNote: nil,
        recommendedAction: "Keep scanning. Everyone is a little bit monster on the inside.",
        trueAgeYears: 29,
        photo: nil
    )
}

extension UIImage {
    /// A drawn stand-in for the subject's photo (no real photos in the repo).
    static let certificatePlaceholder: UIImage = {
        let size = CGSize(width: 480, height: 520)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.35, green: 0.2, blue: 0.6, alpha: 1).cgColor,
                          UIColor(red: 0.1, green: 0.55, blue: 0.6, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            UIColor(white: 1, alpha: 0.35).setFill()
            UIBezierPath(ovalIn: CGRect(x: 150, y: 110, width: 180, height: 200)).fill()
            UIBezierPath(roundedRect: CGRect(x: 70, y: 330, width: 340, height: 260), cornerRadius: 150).fill()
            UIColor(white: 1, alpha: 0.8).setFill()
            for (x, y) in [(60.0, 70.0), (400.0, 120.0), (380.0, 40.0), (90.0, 260.0)] {
                UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 10, height: 10)).fill()
            }
        }
    }()
}

#Preview("Vampire with photo") {
    ScrollView {
        VStack(spacing: 20) {
            CertificateThumbnail(content: .previewVampire)
            ShareCertificateButton(content: .previewVampire)
        }
        .padding()
    }
    .crtScreen()
}

#Preview("Certified human, no photo") {
    ScrollView {
        VStack(spacing: 20) {
            CertificateThumbnail(content: .previewHuman)
            ShareCertificateButton(content: .previewHuman)
        }
        .padding()
    }
    .crtScreen()
}
#endif
