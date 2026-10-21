#if DEBUG && canImport(llama)
import CoreGraphics
import Foundation
import MonsterCore

/// Debug-only M3 checks, run with launch flags on the phone
/// (`-MSRunNotesCheck [set]`, `-MSRunSoak [set]`); results land in
/// Documents/Benchmarks[/set]/ as text files.
nonisolated enum M3Checks {
    /// Spec S-4: 50 AI-written field notes through the kindness checker.
    static func fieldNotesCheck(model: LlamaCppObservationModel, count: Int = 50) async -> String {
        let details: [[String]] = [
            ["red bobble hat", "round glasses"], ["guitar", "fairy lights behind"], ["slice of pizza", "party hat"],
            ["striped scarf", "cup of coffee"], ["headphones", "skateboard"], ["sunglasses", "beach umbrella"],
            ["cat in the background", "knitted jumper"], ["birthday cake", "balloons"], ["denim jacket", "thumbs up"],
            ["bow tie", "bookshelf behind"],
        ]
        let shirts = ["navy blue", "red", "black", "green", "white", "yellow", "gray", "purple"]
        var accepted = 0, dropped = 0, empty = 0, leaked = 0
        var droppedExamples: [String] = []
        var keptExamples: [String] = []
        let start = Date()
        for i in 0..<count {
            let monster = Monster.allCases[i % Monster.allCases.count]
            var input = DossierInput(
                monster: monster, clueEvidence: ["a suspicious reading"], shirtColor: shirts[i % shirts.count],
                confidenceText: "80.0%", caseNumber: "K9-\(1000 + i)", trueAgeYears: 300 + i, seed: UInt64(i) &* 0x9E37_79B9
            )
            input.funDetails = details[i % details.count]
            input.subspecies = Subspecies.name(for: monster, seed: input.seed)
            var filter = DossierStreamFilter(verdict: monster)
            do {
                for try await piece in model.writeDossier(input) {
                    _ = filter.feed(piece)
                    if filter.isFull { break }
                }
            } catch {
                DebugLog.shared.record("Notes check \(i): \(error)")
            }
            _ = filter.finish()
            accepted += filter.acceptedSentences.count
            dropped += filter.rejectedSentences.count
            if filter.acceptedSentences.isEmpty { empty += 1 }
            // Belt and braces: nothing kept may fail the strict check.
            leaked += filter.acceptedSentences.filter { !ContentPolicy.isAllowed(DossierStreamFilter.maskingTrueAge($0), strict: true) }.count
            if droppedExamples.count < 12 { droppedExamples += filter.rejectedSentences.prefix(2).map { "[\(monster.rawValue)] \($0)" } }
            if keptExamples.count < 16 { keptExamples += filter.acceptedSentences.prefix(2).map { "[\(monster.rawValue)] \($0)" } }
        }
        return """
        AI field notes check: \(count) notes in \(String(format: "%.0f", Date().timeIntervalSince(start))) s
        Sentences kept: \(accepted) · dropped by the filter: \(dropped) · notes with nothing kept: \(empty)
        Kept sentences failing the strict check (must be 0): \(leaked)

        Dropped examples:
        \(droppedExamples.joined(separator: "\n"))

        Kept examples:
        \(keptExamples.joined(separator: "\n"))
        """
    }

    /// M3 exit check: 10 back-to-back scans (photo → reveal), timed against
    /// the 12 s budget, with heat and memory per scan.
    @concurrent
    static func soak(model: LlamaCppObservationModel, photos: [URL], scans: Int = 10) async -> String {
        var lines: [String] = []
        var worst = 0.0
        var peak: UInt64 = 0
        for i in 0..<scans {
            let url = photos[i % max(1, photos.count)]
            let start = Date()
            guard let data = try? Data(contentsOf: url),
                  let photo = try? PhotoPreparer.prepare(data: data, source: .library) else { continue }
            let faces = FaceAnalyzer.detectFaces(in: photo.displayImage)
            _ = ClassicScanner.measure(photo: photo, faces: faces, scene: SceneClassifier.classify(photo.displayImage), batteryLevel: nil)
            let crop = faces.first.flatMap { ScanSession.subjectCrop(photo.displayImage, face: $0.box) } ?? photo.displayImage
            let tooHot = ModelService.isTooHot
            var run = ObservationRun()
            if !tooHot { run = await model.observeDetailed(image: crop, timeout: 20, chaos: false) }
            let pipeline = Date().timeIntervalSince(start)
            // What the player sees: the scan animation runs at least 5.5 s, and the
            // scan stops waiting for the model at 10.3 s.
            let missedDeadline = pipeline > 10.3
            let reveal = min(max(5.5, pipeline), 11.0) + 0.75 // + blackout before the card
            worst = max(worst, reveal)
            peak = max(peak, MemoryProbe.footprintBytes)
            lines.append(String(
                format: "scan %2d  model %5.2f s  reveal at %5.2f s  %@  thermal %d  footprint %@",
                i + 1, run.seconds, reveal,
                tooHot ? "CLASSIC (hot)" : (run.observations == nil || missedDeadline ? "CLASSIC (fallback)" : "AI"),
                ProcessInfo.processInfo.thermalState.rawValue, MemoryProbe.megabytes(MemoryProbe.footprintBytes)
            ))
        }
        return (["10-scan soak (no crash if you can read this)"] + lines + [
            String(format: "Worst shutter-to-reveal: %.2f s (budget 12 s) · peak footprint %@", worst, MemoryProbe.megabytes(peak)),
        ]).joined(separator: "\n")
    }

    @MainActor
    static func run(flag: String, set: String?, models: ModelService) async {
        await models.prepare()
        while models.status == .verifying || models.status == .loading { try? await Task.sleep(for: .milliseconds(200)) }
        let folder = ModelBenchmark.folder(set: set)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let model = models.observer as? LlamaCppObservationModel else {
            try? "M3 check needs the model; status: \(models.bootLine)".write(
                to: folder.appendingPathComponent("summary-latest.txt"), atomically: true, encoding: .utf8)
            return
        }
        let text: String
        if flag == "-MSRunNotesCheck" {
            text = await fieldNotesCheck(model: model)
        } else {
            let photos = ((try? FileManager.default.contentsOfDirectory(
                at: folder.appendingPathComponent("photos"), includingPropertiesForKeys: nil)) ?? [])
                .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            text = await soak(model: model, photos: photos)
        }
        try? text.write(to: folder.appendingPathComponent("summary-latest.txt"), atomically: true, encoding: .utf8)
        DebugLog.shared.record(text)
    }
}
#endif
