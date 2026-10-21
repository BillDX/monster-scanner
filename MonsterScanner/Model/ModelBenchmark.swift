#if DEBUG && canImport(llama)
import CoreGraphics
import Foundation
import MonsterCore
import Observation
import SwiftUI

/// Debug-only M2 benchmark (spec section 2): runs every photo in
/// Documents/Benchmarks/photos through the model and Classic Mode, compares
/// both with Documents/Benchmarks/labels.csv, and writes a CSV report.
///
/// labels.csv columns: file,hair_color,eye_color,shirt_color,age_band,expression,accessories
/// (accessories separated by ";", or "none").
nonisolated enum ModelBenchmark {
    struct Label: Sendable {
        var hair: HairColor, eyes: EyeColor, shirt: ColorFamily, age: AgeBand, expression: FaceExpression
        var accessories: Set<Accessory>
    }

    struct Row: Sendable {
        var file: String
        var run: ObservationRun
        /// Photo prep + Vision + classic measurements + model, end to end.
        var pipelineSeconds: Double
        var classic: SubjectObservations?
        var modelMatches: Int?
        var classicMatches: Int?
        var fields = 6
        var footprintMB: Double
    }

    struct Report: Sendable {
        var modelName: String
        var loadSeconds: Double
        var verifySeconds: Double?
        var peakFootprintMB: Double
        var rows: [Row]
        var csvPath: String

        var summary: String {
            let times = rows.map(\.run.seconds)
            let pipeline = rows.map(\.pipelineSeconds)
            let valid = rows.filter { $0.run.observations != nil }.count
            let firstTry = rows.filter(\.run.firstAttemptParsed).count
            let labelled = rows.filter { $0.modelMatches != nil }
            let modelAccuracy = labelled.isEmpty ? nil
                : Double(labelled.reduce(0) { $0 + ($1.modelMatches ?? 0) }) / Double(labelled.count * 6)
            let classicAccuracy = labelled.isEmpty ? nil
                : Double(labelled.reduce(0) { $0 + ($1.classicMatches ?? 0) }) / Double(labelled.count * 6)
            return [
                "\(modelName) on \(rows.count) photos",
                String(format: "SHA-256 check: %.2f s · Load: %.2f s · Peak footprint: %.0f MB", verifySeconds ?? -1, loadSeconds, peakFootprintMB),
                String(format: "Model s/scan: mean %.2f, max %.2f (first %.2f)", times.reduce(0, +) / Double(max(1, times.count)), times.max() ?? 0, times.first ?? 0),
                String(format: "Whole pipeline s/photo: mean %.2f, max %.2f", pipeline.reduce(0, +) / Double(max(1, pipeline.count)), pipeline.max() ?? 0),
                "Per photo (model s): " + times.map { String(format: "%.2f", $0) }.joined(separator: ", "),
                "Valid JSON: \(valid)/\(rows.count) (first try \(firstTry)/\(rows.count))",
                modelAccuracy.map { String(format: "Attribute accuracy (model): %.0f%% over %d labelled photos", $0 * 100, labelled.count) }
                    ?? "Attribute accuracy: no labels.csv",
                classicAccuracy.map { String(format: "Attribute accuracy (Classic): %.0f%%", $0 * 100) } ?? "",
                "CSV: \(csvPath)",
            ].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    static var folder: URL { folder(set: nil) }

    /// Documents/Benchmarks, or Documents/Benchmarks/<set> for a named run.
    static func folder(set: String?) -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Benchmarks", isDirectory: true)
        guard let set, !set.isEmpty else { return root }
        return root.appendingPathComponent(set, isDirectory: true)
    }

    /// Benchmarks an already-loaded model (load and verify times come from
    /// `ModelService`, measured at app launch).
    @concurrent
    static func run(
        model: LlamaCppObservationModel, pack: ModelPack, loadSeconds: Double, verifySeconds: Double?,
        set: String? = nil, progress: @escaping @Sendable (String) -> Void
    ) async throws -> Report {
        let folder = folder(set: set)
        let photosFolder = folder.appendingPathComponent("photos", isDirectory: true)
        let files = ((try? FileManager.default.contentsOfDirectory(at: photosFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let labels = loadLabels(in: folder)

        let peak = PeakSampler()
        peak.start()
        defer { peak.stop() }

        var rows: [Row] = []
        for (index, url) in files.enumerated() {
            progress("Photo \(index + 1)/\(files.count): \(url.lastPathComponent)")
            let pipelineStart = Date()
            guard let data = try? Data(contentsOf: url),
                  let photo = try? PhotoPreparer.prepare(data: data, source: .library) else { continue }
            let faces = FaceAnalyzer.detectFaces(in: photo.displayImage)
            let crop = faces.first.flatMap { ScanSession.subjectCrop(photo.displayImage, face: $0.box) } ?? photo.displayImage
            let run = await model.observeDetailed(image: crop, timeout: LlamaCppObservationModel.callTimeout)
            let classic = ClassicScanner.measure(
                photo: photo, faces: faces, scene: SceneClassifier.classify(photo.displayImage), batteryLevel: nil
            ).observations

            var row = Row(file: url.lastPathComponent, run: run, pipelineSeconds: Date().timeIntervalSince(pipelineStart),
                          classic: classic, footprintMB: Double(MemoryProbe.footprintBytes) / 1_048_576)
            if let label = labels[url.lastPathComponent] {
                row.modelMatches = run.observations.map { matches($0, label) } ?? 0
                row.classicMatches = matches(classic, label)
            }
            rows.append(row)
        }
        let csv = try writeCSV(rows: rows, model: pack.displayName, loadSeconds: loadSeconds, peak: peak.peakMB, in: folder)
        return Report(modelName: pack.displayName, loadSeconds: loadSeconds, verifySeconds: verifySeconds,
                      peakFootprintMB: peak.peakMB, rows: rows, csvPath: csv)
    }

    // MARK: Scoring

    static func matches(_ o: SubjectObservations, _ l: Label) -> Int {
        [o.hairColor == l.hair, o.eyeColor == l.eyes, o.shirtFamily == l.shirt, o.ageBand == l.age,
         o.expression == l.expression, o.wornAccessories == l.accessories].filter { $0 }.count
    }

    static func loadLabels(in folder: URL) -> [String: Label] {
        guard let text = try? String(contentsOf: folder.appendingPathComponent("labels.csv"), encoding: .utf8) else { return [:] }
        var labels: [String: Label] = [:]
        for line in text.split(whereSeparator: \.isNewline).dropFirst() {
            let c = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count >= 7 else { continue }
            let accessories = Set(c[6].split(separator: ";").compactMap { Accessory(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
                .subtracting([.none])
            labels[c[0]] = Label(
                hair: HairColor(rawValue: c[1]) ?? .unknown, eyes: EyeColor(rawValue: c[2]) ?? .unknown,
                shirt: ColorFamily(name: c[3]), age: AgeBand(rawValue: c[4]) ?? .unknown,
                expression: FaceExpression(rawValue: c[5]) ?? .unknown, accessories: accessories
            )
        }
        return labels
    }

    static func writeCSV(rows: [Row], model: String, loadSeconds: Double, peak: Double, in folder: URL) throws -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "'") + "\"" }
        var lines = ["model,runtime,file,load_s,seconds,pipeline_s,prefill_s,gen_tokens,attempts,first_try_json,valid_json,hair,eyes,shirt,age,expression,accessories,background,model_matches,classic_matches,fields,footprint_mb,peak_mb,error"]
        for r in rows {
            let o = r.run.observations
            lines.append([
                q(model), "llama.cpp b11799", q(r.file), String(format: "%.2f", loadSeconds),
                String(format: "%.2f", r.run.seconds), String(format: "%.2f", r.pipelineSeconds),
                String(format: "%.2f", r.run.prefillSeconds),
                "\(r.run.generatedTokens)", "\(r.run.attempts)", "\(r.run.firstAttemptParsed)", "\(o != nil)",
                o?.hairColor.rawValue ?? "", o?.eyeColor.rawValue ?? "", q(o?.shirtColor ?? ""), o?.ageBand.rawValue ?? "",
                o?.expression.rawValue ?? "", q(o?.accessories.map(\.rawValue).joined(separator: ";") ?? ""),
                q(o?.backgroundHint ?? ""), r.modelMatches.map(String.init) ?? "", r.classicMatches.map(String.init) ?? "",
                "\(r.fields)", String(format: "%.0f", r.footprintMB), String(format: "%.0f", peak), q(r.run.error ?? ""),
            ].joined(separator: ","))
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "")
        let url = folder.appendingPathComponent("results-\(stamp).csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url.lastPathComponent
    }
}

extension ModelBenchmark {
    /// Waits for the app's own launch-time verify + load, then benchmarks
    /// that loaded model. Writes summary-latest.txt next to the CSV.
    @MainActor
    static func runWithService(
        _ models: ModelService, set: String? = nil, progress: @escaping @Sendable (String) -> Void
    ) async -> String {
        progress("Waiting for the model to verify and load…")
        await models.prepare()
        while models.status == .verifying || models.status == .loading {
            try? await Task.sleep(for: .milliseconds(200))
        }
        let text: String
        if let model = models.observer as? LlamaCppObservationModel, let load = models.lastLoadSeconds {
            do {
                let report = try await run(
                    model: model, pack: models.pack, loadSeconds: load, verifySeconds: models.lastVerifySeconds,
                    set: set, progress: progress
                )
                text = report.summary
            } catch {
                text = "Benchmark failed: \(error)"
            }
        } else {
            text = "Benchmark needs the model ready; status: \(models.bootLine)"
        }
        let folder = folder(set: set)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? text.write(to: folder.appendingPathComponent("summary-latest.txt"), atomically: true, encoding: .utf8)
        DebugLog.shared.record("Benchmark:\n" + text)
        return text
    }
}

/// Samples the memory footprint every 50 ms to catch the peak.
nonisolated final class PeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private var task: Task<Void, Never>?

    var peakMB: Double { lock.withLock { Double(peak) / 1_048_576 } }

    func start() {
        task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.record(MemoryProbe.footprintBytes)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func record(_ bytes: UInt64) {
        lock.withLock { peak = max(peak, bytes) }
    }

    func stop() { task?.cancel() }
}

struct BenchmarkView: View {
    @Environment(AppModel.self) private var app
    @State private var status = "Copy photos to Documents/Benchmarks/photos (and labels.csv to Documents/Benchmarks), then run."
    @State private var running = false

    var body: some View {
        List {
            Section {
                Button(running ? "Running…" : "Run benchmark") { Task { await run() } }
                    .disabled(running || !app.models.isInstalled)
            }
            Section("Result") {
                Text(status).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .navigationTitle("Model benchmark")
    }

    private func run() async {
        running = true
        defer { running = false }
        status = await ModelBenchmark.runWithService(app.models) { message in
            Task { @MainActor in status = message }
        }
    }
}
#endif
