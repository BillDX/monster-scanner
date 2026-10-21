import MonsterCore
import SwiftUI

/// Fake BIOS boot sequence. In M0 this is the whole app; later milestones
/// hand off to the consent gate and scanner from here.
struct BootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleLines = 0

    private let lines = [
        "BUREAU OF SECRET MONSTER AFFAIRS",
        "FIELD SCANNER BIOS v0.1.0",
        "",
        "Calibrating ectoplasm sensors… OK",
        "Polishing garlic detectors… OK",
        "Aligning alien antenna array… OK",
        "Charging silver-bullet capacitors… OK",
        "Consulting the moon… OK",
        "",
        "AI MODEL: NOT INSTALLED",
        "MODE: CLASSIC (backup crystals)",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.prefix(visibleLines).enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(Theme.mono(.footnote))
                    .foregroundStyle(Theme.neon)
                    .crtGlow()
            }

            if visibleLines >= lines.count {
                roster
                    .padding(.top, 24)
                    .transition(.opacity)
            }

            Spacer()

            Text("BUILD M0 · SCANNER ARRIVES IN M1")
                .font(Theme.mono(.caption2))
                .foregroundStyle(Theme.dimNeon)
        }
        .padding(20)
        .crtScreen()
        .task { await runBootSequence() }
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KNOWN ENTITIES ON FILE")
                .font(Theme.mono(.caption, weight: .bold))
                .foregroundStyle(Theme.alert)
                .crtGlow(Theme.alert, radius: 4)
            Text(Monster.allCases.map(\.emoji).joined(separator: "  "))
                .font(.title)
                .accessibilityLabel(
                    "Known entities: " + Monster.allCases.map(\.rawValue).joined(separator: ", ")
                )
        }
    }

    private func runBootSequence() async {
        guard !reduceMotion else {
            visibleLines = lines.count
            return
        }
        for index in lines.indices {
            try? await Task.sleep(for: .milliseconds(lines[index].isEmpty ? 120 : 260))
            withAnimation(.easeOut(duration: 0.15)) { visibleLines = index + 1 }
        }
    }
}

#Preview {
    BootView()
        .preferredColorScheme(.dark)
}
