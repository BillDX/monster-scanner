import MonsterCore
import SwiftUI

/// Fake BIOS boot sequence. Tap to skip.
struct BootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleLines = 0

    private var lines: [String] {
        [
            "BUREAU OF SECRET MONSTER AFFAIRS",
            "FIELD SCANNER BIOS v\(Self.version)",
            "",
            "Calibrating ectoplasm sensors… OK",
            "Polishing garlic detectors… OK",
            "Aligning alien antenna array… OK",
            "Charging silver-bullet capacitors… OK",
            "Consulting the moon… \(Int((MoonPhase.illumination(at: .now) * 100).rounded()))% FULL",
            "",
            "AI MODEL: NOT INSTALLED",
            "MODE: \(app.modeLabel)",
        ]
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.prefix(visibleLines).enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(Theme.mono(.footnote))
                    .foregroundStyle(Theme.neon)
                    .crtGlow()
            }

            if visibleLines >= lines.count {
                VStack(alignment: .leading, spacing: 8) {
                    Text("KNOWN ENTITIES ON FILE")
                        .font(Theme.mono(.caption, weight: .bold))
                        .foregroundStyle(Theme.alert)
                        .crtGlow(Theme.alert, radius: 4)
                    Text(Monster.allCases.map(\.emoji).joined(separator: "  "))
                        .font(.title)
                        .accessibilityLabel("Known entities: " + Monster.allCases.map(\.rawValue).joined(separator: ", "))
                }
                .padding(.top, 24)
                .transition(.opacity)
            }

            Spacer()

            Text(visibleLines >= lines.count ? "TAP TO CONTINUE" : "TAP TO SKIP")
                .font(Theme.mono(.caption, weight: .bold))
                .foregroundStyle(Theme.dimNeon)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .crtScreen()
        .contentShape(Rectangle())
        .onTapGesture { app.finishBoot() }
        .accessibilityAction(named: "Continue") { app.finishBoot() }
        .task { await runBootSequence() }
    }

    private func runBootSequence() async {
        if reduceMotion {
            visibleLines = lines.count
        } else {
            for index in lines.indices {
                try? await Task.sleep(for: .milliseconds(lines[index].isEmpty ? 100 : 230))
                withAnimation(.easeOut(duration: 0.15)) { visibleLines = index + 1 }
            }
        }
        try? await Task.sleep(for: .seconds(1.6))
        app.finishBoot()
    }
}
