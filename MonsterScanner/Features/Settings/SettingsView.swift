import MonsterCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showingConsent = false
    @State private var showingHowItWorks = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section("Scanner") {
                    Toggle("Agent voice", isOn: $app.voiceEnabled)
                    Toggle("Haptics", isOn: $app.hapticsEnabled)
                    LabeledContent("Mode", value: "Classic (no AI model)")
                }
                Section("The promise") {
                    Button("Review the consent promise") { showingConsent = true }
                    Button("How it works") { showingHowItWorks = true }
                }
                Section("About") {
                    LabeledContent("Version", value: BootView.version)
                    LabeledContent("Network", value: "None")
                    NavigationLink("Debug log") { DebugView() }
                }
            }
            .font(Theme.mono(.body))
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(isPresented: $showingConsent) {
            ConsentView(onAccept: { app.acceptConsent() }, showsClose: true)
        }
        .sheet(isPresented: $showingHowItWorks) { HowItWorksView() }
    }
}

/// On-device only: fallbacks, errors, and the last scan's raw numbers.
struct DebugView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            if let analysis = app.session?.analysis {
                Section("Last scan: measurements") {
                    let m = analysis.evidence.measurements
                    row("Faces", "\(m.faceCount)")
                    row("Face area", m.faceAreaFraction.map { String(format: "%.3f", $0) } ?? "–")
                    row("Centre offset", m.faceCenterOffset.map { String(format: "%.3f", $0) } ?? "–")
                    row("Roll / yaw", "\(fmt(m.headRollDegrees)) / \(fmt(m.headYawDegrees))")
                    row("Brightness", String(format: "%.3f", m.brightness))
                    row("Blur variance", String(format: "%.0f", m.blurVariance))
                    row("Moon", String(format: "%.3f (%@)", m.moonIllumination, analysis.moonName))
                    row("Time", m.clockText)
                    row("Battery", m.batteryLevel.map { String(format: "%.2f", $0) } ?? "unknown")
                    row("Shirt hue", m.shirtHueDegrees.map { String(format: "%.0f°", $0) } ?? "–")
                    if let face = analysis.subject {
                        row("Mouth / eye ratio", "\(fmt(face.mouthOpenRatio, digits: 2)) / \(fmt(face.eyeOpenRatio, digits: 2))")
                        row("Smile / eyes closed", "\(face.isSmiling) / \(face.eyesClosed)")
                    }
                }
                if let verdict = app.session?.verdict {
                    Section("Last scan: scores (threshold \(VerdictEngine.humanThreshold))") {
                        ForEach(verdict.scores, id: \.monster) { score in
                            row(score.monster.rawValue, String(format: "%.2f + %.2f = %.2f", score.cluePoints, score.anomaly, score.total))
                        }
                    }
                }
            }
            Section("Log") {
                let entries = DebugLog.shared.entries.reversed()
                if entries.isEmpty {
                    Text("Nothing logged.").foregroundStyle(.secondary)
                }
                ForEach(Array(entries)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary)
                        Text(entry.message).font(.caption)
                    }
                }
            }
        }
        .font(Theme.mono(.caption))
        .navigationTitle("Debug")
    }

    private func row(_ name: String, _ value: String) -> some View {
        LabeledContent(name, value: value)
    }

    private func fmt(_ value: Double?, digits: Int = 1) -> String {
        value.map { String(format: "%.\(digits)f", $0) } ?? "–"
    }
}
