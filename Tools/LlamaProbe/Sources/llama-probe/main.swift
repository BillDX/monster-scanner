import CoreGraphics
import Foundation
import ImageIO
import MonsterCore

// Usage: llama-probe <model.gguf> <mmproj.gguf> [--no-grammar] [--gpu 0] [--max-image-tokens N] <image>...
var args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3 else {
    print("usage: llama-probe <model.gguf> <mmproj.gguf> [--no-grammar] [--gpu N] [--max-image-tokens N] <image>...")
    exit(2)
}
let modelPath = args.removeFirst()
let projectorPath = args.removeFirst()
var useGrammar = true
var gpuLayers: Int32 = 99
var maxImageTokens: Int32 = 0
var temperature: Float = 0
var compact = false
var dossierMode = false
var withExample = false
var notesMode = false
var forcedVerdict: Monster?
var images: [String] = []
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--no-grammar": useGrammar = false
    case "--gpu": gpuLayers = Int32(args.removeFirst()) ?? 99
    case "--max-image-tokens": maxImageTokens = Int32(args.removeFirst()) ?? 0
    case "--temp": temperature = Float(args.removeFirst()) ?? 0
    case "--compact": compact = true
    case "--dossier": dossierMode = true
    case "--example": withExample = true
    case "--notes": notesMode = true; dossierMode = true
    case "--verdict": forcedVerdict = Monster(rawValue: args.removeFirst())
    default: images.append(a)
    }
}

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 1024,
    ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
}

let engine = LlamaEngine(configuration: .init(
    modelPath: modelPath, projectorPath: projectorPath, gpuLayers: gpuLayers, imageMaxTokens: maxImageTokens
))
do {
    let loadSeconds = try await engine.load()
    print(String(format: "loaded in %.2f s (gpu layers %d, grammar %@)", loadSeconds, gpuLayers, useGrammar ? "on" : "off"))
    for path in images {
        guard let image = loadImage(path), let rgb = ImageBytes.rgb(from: image, maxPixels: 512) else {
            print("✗ can't read \(path)"); continue
        }
        let start = Date()
        let result = try await engine.generate(
            system: ObservationPrompt.system, user: ObservationPrompt.user,
            image: .init(width: rgb.width, height: rgb.height, bytes: rgb.bytes),
            grammar: useGrammar ? (compact ? ObservationPrompt.grammar.replacingOccurrences(of: "ws ::= [ \\t\\n]{0,3}", with: "ws ::= \" \"?") : ObservationPrompt.grammar) : nil,
            maxTokens: ObservationPrompt.maxTokens,
            temperature: temperature,
            seed: UInt32(truncatingIfNeeded: rgb.bytes.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 })
        )
        let total = Date().timeIntervalSince(start)
        print("\n== \((path as NSString).lastPathComponent) (\(rgb.width)x\(rgb.height))")
        print(String(format: "prompt %d tok, prefill %.2f s, generated %d tok in %.2f s (%.1f tok/s), total %.2f s",
                     result.promptTokens, result.prefillSeconds, result.generatedTokens, result.generateSeconds,
                     Double(result.generatedTokens) / max(0.001, result.generateSeconds), total))
        print("raw: \(result.text)")
        switch ObservationParser.parse(result.text) {
        case .success(let o):
            print("parsed: hair=\(o.hairColor.rawValue) eyes=\(o.eyeColor.rawValue) shirt=\(o.shirtColor) age=\(o.ageBand.rawValue) expr=\(o.expression.rawValue) acc=\(o.accessories.map(\.rawValue)) bg=\(o.backgroundHint)")
            print("  read:    \(o.expressionRead ?? "—")")
            print("  details: \(o.funDetails)")
            print("  vibe:    \(o.vibe ?? "—")")
        case .failure(let f):
            print("PARSE FAILED: \(f)")
        }
        if dossierMode, case .success(let observations) = ObservationParser.parse(result.text) {
            let evidence = ScanEvidence(measurements: Measurements(minutesSinceMidnight: 21 * 60 + 30), observations: observations)
            var verdict = VerdictEngine.decide(evidence, seed: UInt64(rgb.bytes.count) &* 2654435761)
            if let forcedVerdict, forcedVerdict != verdict.monster {
                verdict = VerdictEngine.decide(Fixtures.strongEvidence(forcedVerdict), seed: verdict.seed)
            }
            let input = DossierInput(verdict: verdict, observations: observations)
            print("-- verdict \(verdict.monster.rawValue) (\(input.subspecies ?? "")), clues: \(input.clueEvidence)")
            var filter = DossierStreamFilter(verdict: verdict.monster)
            let start = Date()
            let collected = DossierCollector()
            let dossierResult = try await engine.generate(
                system: DossierPrompt.system,
                user: notesMode ? DossierPrompt.fieldNotesUser(for: input) : DossierPrompt.user(for: input, styleExample: withExample),
                image: nil,
                grammar: notesMode ? DossierPrompt.fieldNotesGrammar : DossierPrompt.grammar,
                maxTokens: notesMode ? DossierPrompt.fieldNotesMaxTokens : DossierPrompt.maxTokens,
                temperature: DossierPrompt.temperature, seed: UInt32(truncatingIfNeeded: verdict.seed), repeatPenalty: DossierPrompt.repeatPenalty,
                onPiece: { piece in collected.append(piece); return true }
            )
            for piece in collected.pieces { _ = filter.feed(piece) }
            if notesMode { _ = filter.feed("\n\nRecommended action: (template)") }
            _ = filter.finish()
            print(String(format: "-- dossier: prompt %d tok, %d tok generated, prefill %.2f s, total %.2f s",
                         dossierResult.promptTokens, dossierResult.generatedTokens, dossierResult.prefillSeconds, Date().timeIntervalSince(start)))
            for sentence in filter.acceptedSentences { print("   ✓ " + sentence) }
            for sentence in filter.rejectedSentences { print("   ✗ " + sentence) }
            print("   ACTION: \(filter.recommendedAction ?? "—")   usable: \(filter.isUsable)")
        }
    }
    // Free Metal resources before exit, or ggml asserts in its static destructor.
    await engine.unload()
} catch {
    print("error: \(error)")
    await engine.unload()
    exit(1)
}

final class DossierCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ piece: String) { lock.lock(); storage.append(piece); lock.unlock() }
    var pieces: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}

enum Fixtures {
    /// Minimal strong evidence per monster, to force a verdict for testing dossiers.
    static func strongEvidence(_ monster: Monster) -> ScanEvidence {
        var m = Measurements()
        var o = SubjectObservations()
        switch monster {
        case .vampire: o.shirtColor = "black"; o.accessories = [.sunglasses]; o.backgroundHint = "living room"; m.minutesSinceMidnight = 23 * 60
        case .alien: o.shirtColor = "lime green"; o.expression = .surprised; m.headRollDegrees = 20
        case .kaiju: o.shirtColor = "gray"; o.expression = .sillyFace; m.faceAreaFraction = 0.45
        case .werewolf: o.accessories = [.hood]; m.moonIllumination = 0.97; m.minutesSinceMidnight = 20 * 60
        case .zombie: o.expression = .sleepy; m.minutesSinceMidnight = 6 * 60; m.brightness = 0.25
        case .robot: o.shirtColor = "blue"; o.expression = .serious; o.accessories = [.headphones]; m.headRollDegrees = 0.5
        case .ghost: o.shirtColor = "white"; m.blurVariance = 30; m.brightness = 0.9
        case .human: break
        }
        return ScanEvidence(measurements: m, observations: o)
    }
}
