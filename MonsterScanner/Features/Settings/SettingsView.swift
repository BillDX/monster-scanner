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
                    Toggle("Sound effects", isOn: $app.soundsEnabled)
                    Toggle("Haptics", isOn: $app.hapticsEnabled)
                }
                Section {
                    Toggle("Chaos Mode", isOn: $app.chaosMode)
                    Toggle("AI field notes (experimental)", isOn: $app.aiFieldNotes)
                } header: {
                    Text("Mischief")
                } footer: {
                    Text("Chaos Mode lets the AI pick the verdict instead of the Bureau's rules. AI field notes adds Agent K-9's own scribbles after the dossier; small AIs are not great comedians, so results vary. Both need the AI observer.")
                }
                ModelSettingsSection(models: app.models)
                Section("The promise") {
                    Button("Review the consent promise") { showingConsent = true }
                    Button("How it works") { showingHowItWorks = true }
                }
                Section("About") {
                    LabeledContent("Version", value: BootView.version)
                    LabeledContent("Network", value: "Model download only")
                    Link("Privacy policy", destination: URL(string: "https://billdx.github.io/monster-scanner/privacy/")!)
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

/// Download, status and removal of the AI model.
struct ModelSettingsSection: View {
    @Bindable var models: ModelService

    var body: some View {
        Section {
            Toggle("Use the AI observer", isOn: $models.aiEnabled)
            LabeledContent("Model", value: "\(models.pack.displayName) · \(models.pack.sizeText)")
            LabeledContent("Status", value: statusText)
            switch models.status {
            case .unsupported:
                Text("The AI model runs on iPhone only. The Simulator uses Classic Mode.")
                    .foregroundStyle(.secondary)
            case .needsMoreMemory:
                Text("The AI observer needs an iPhone with 6 GB of memory or more (iPhone 12 Pro, 13 Pro, 14 or newer). This iPhone plays Classic Mode, with every verdict and joke.")
                    .foregroundStyle(.secondary)
                if ModelStore.isInstalled(models.pack) {
                    Button("Delete model", role: .destructive) { models.deleteModel() }
                }
            case .notInstalled, .failed:
                Button("Download (\(models.pack.sizeText))") { models.download() }
                Toggle("Allow cellular data", isOn: $models.allowCellular)
            case .downloading(let fraction):
                ProgressView(value: fraction)
                Button("Cancel download", role: .destructive) { models.cancelDownload() }
            case .ready, .sleeping, .verifying, .loading:
                Button("Delete model", role: .destructive) { models.deleteModel() }
            }
        } header: {
            Text("AI observer")
        } footer: {
            if models.deviceSupportsModel {
                Text("Downloaded once over HTTPS from Qwen's official Hugging Face repo (Apache 2.0) and checked with SHA-256. After that the app never uses the network. Wi-Fi recommended.")
            } else {
                Text("Nothing is downloaded on this iPhone, and the app never uses the network.")
            }
        }
    }

    private var statusText: String {
        switch models.status {
        case .unsupported: "Not available here"
        case .needsMoreMemory: "Needs a 6 GB iPhone"
        case .notInstalled: "Not downloaded"
        case .downloading(let f): "Downloading \(Int(f * 100))%"
        case .verifying: "Checking SHA-256…"
        case .loading: "Loading…"
        case .ready: "Ready"
        case .sleeping: "Installed (asleep)"
        case .failed(let message): message
        }
    }
}

/// On-device only: fallbacks, errors, and the last scan's raw numbers.
struct DebugView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section("Verdict tally (Chaos experiment)") {
                let monsters = Monster.allCases
                ForEach(monsters, id: \.self) { monster in
                    row(monster.rawValue, "code \(app.tally["code." + monster.rawValue] ?? 0) · chaos \(app.tally["chaos." + monster.rawValue] ?? 0)")
                }
                Button("Reset tally", role: .destructive) { app.resetTally() }
            }
            Section("Memory and model") {
                row("Footprint", MemoryProbe.megabytes(MemoryProbe.footprintBytes))
                row("Available before limit", MemoryProbe.megabytes(MemoryProbe.availableBytes))
                row("Thermal state", "\(ProcessInfo.processInfo.thermalState.rawValue) (0 nominal … 3 critical)")
                row("Model status", app.models.bootLine)
                row("Verify / load", "\(fmt(app.models.lastVerifySeconds)) s / \(fmt(app.models.lastLoadSeconds)) s")
                #if DEBUG && canImport(llama)
                NavigationLink("Model benchmark") { BenchmarkView() }
                #endif
            }
            if let run = app.session?.modelRun {
                Section("Last scan: AI observer") {
                    row("Time", String(format: "%.2f s (prefill %.2f s)", run.seconds, run.prefillSeconds))
                    row("Tokens", "\(run.promptTokens) in / \(run.generatedTokens) out")
                    row("Attempts", "\(run.attempts)\(run.firstAttemptParsed ? "" : " (retry)")")
                    if let error = run.error { row("Error", error) }
                    ForEach(Array(run.rawOutputs.enumerated()), id: \.offset) { _, raw in
                        Text(raw).font(.caption2.monospaced())
                    }
                }
            }
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
