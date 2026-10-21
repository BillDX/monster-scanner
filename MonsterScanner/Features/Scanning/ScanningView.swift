import MonsterCore
import SwiftUI

/// The 5–10 second dramatic scan: radar sweep over the photo, a rising
/// "Monster Probability" gauge, and telemetry lines with real measurements.
struct ScanningView: View {
    let session: ScanSession
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("SCAN IN PROGRESS")
                    .font(Theme.mono(.headline, weight: .bold))
                    .foregroundStyle(Theme.alert)
                    .crtGlow(Theme.alert, radius: 5)
                Spacer()
                Button("ABORT") { app.scanAgain() }
                    .font(Theme.mono(.caption, weight: .bold))
                    .foregroundStyle(Theme.dimNeon)
                    .accessibilityLabel("Abort scan")
            }

            photo
                .frame(maxHeight: 340)

            gauge

            telemetry
        }
        .padding(20)
        .crtScreen()
        .accessibilityElement(children: .contain)
    }

    // MARK: Photo + radar

    private var photo: some View {
        ZStack {
            if let image = session.displayImage {
                GeometryReader { geo in
                    let aspect = image.size.width / max(1, image.size.height)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .colorMultiply(Color(red: 0.6, green: 1, blue: 0.7))
                            .accessibilityLabel("The photo being scanned")
                        if let face = session.analysis?.subject?.box {
                            let rect = BoxMapper.rect(for: face, aspect: aspect, in: geo.size, fill: false)
                            Reticle(label: "SUBJECT")
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                        }
                    }
                }
            } else {
                Rectangle().fill(Color.black)
                Text("DEVELOPING FILM…")
                    .font(Theme.mono(.caption, weight: .bold))
                    .foregroundStyle(Theme.dimNeon)
            }
            RadarSweep(animated: !reduceMotion)
            ScanLines(opacity: 0.15)
        }
        .clipShape(Rectangle())
        .overlay(Rectangle().stroke(Theme.neon.opacity(0.6), lineWidth: 1))
    }

    // MARK: Gauge

    private var gauge: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MONSTER PROBABILITY")
                Spacer()
                Text(String(format: "%.1f%%", session.gauge))
                    .monospacedDigit()
            }
            .font(Theme.mono(.subheadline, weight: .bold))
            .foregroundStyle(Theme.neon)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.neon.opacity(0.12))
                    Rectangle()
                        .fill(LinearGradient(colors: [Theme.neon, Theme.alert], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * session.gauge / 100)
                        .animation(.easeOut(duration: 0.3), value: session.gauge)
                }
            }
            .frame(height: 14)
            .overlay(Rectangle().stroke(Theme.neon.opacity(0.7), lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monster probability")
        .accessibilityValue(String(format: "%.0f percent", session.gauge))
    }

    // MARK: Telemetry

    private var telemetry: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(session.lines.enumerated()), id: \.offset) { index, line in
                        Text("> " + line)
                            .font(Theme.mono(.caption))
                            .foregroundStyle(index == session.lines.count - 1 ? Theme.neon : Theme.dimNeon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: session.lines.count) { _, count in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityLabel("Scanner telemetry")
    }
}

/// A rotating radar wedge.
struct RadarSweep: View {
    var animated = true

    var body: some View {
        TimelineView(.animation(paused: !animated)) { timeline in
            let angle = animated ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360 : 30
            GeometryReader { geo in
                let size = max(geo.size.width, geo.size.height) * 1.5
                AngularGradient(
                    colors: [Theme.neon.opacity(0), Theme.neon.opacity(0), Theme.neon.opacity(0.45)],
                    center: .center, startAngle: .degrees(0), endAngle: .degrees(360)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(angle))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
