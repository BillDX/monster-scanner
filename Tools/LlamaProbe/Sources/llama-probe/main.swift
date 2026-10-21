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
var images: [String] = []
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--no-grammar": useGrammar = false
    case "--gpu": gpuLayers = Int32(args.removeFirst()) ?? 99
    case "--max-image-tokens": maxImageTokens = Int32(args.removeFirst()) ?? 0
    case "--temp": temperature = Float(args.removeFirst()) ?? 0
    case "--compact": compact = true
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
    }
    // Free Metal resources before exit, or ggml asserts in its static destructor.
    await engine.unload()
} catch {
    print("error: \(error)")
    await engine.unload()
    exit(1)
}
