#if canImport(llama)
import CoreGraphics
import Foundation
import MonsterCore

/// Runtime A: llama.cpp + mtmd running Qwen3-VL-2B on Metal.
nonisolated final class LlamaCppObservationModel: ObservationModel {
    let displayName: String
    private let engine: LlamaEngine
    /// Spec section 6: every model call times out after 20 s.
    static let callTimeout: TimeInterval = 20

    init(displayName: String, modelPath: String, projectorPath: String) {
        self.displayName = displayName
        engine = LlamaEngine(configuration: .init(modelPath: modelPath, projectorPath: projectorPath))
    }

    /// Loads the model. Returns load seconds (0 if already loaded).
    @discardableResult
    func load() async throws -> Double {
        try await engine.load()
    }

    func prewarm() async throws {
        try await load()
    }

    func observe(image: CGImage) async throws -> SubjectObservations {
        let run = await observeDetailed(image: image)
        guard let observations = run.observations else { throw ObservationError.invalidOutput }
        return observations
    }

    /// One observation with a single retry on unparseable output (spec 4.1).
    func observeDetailed(image: CGImage, timeout: TimeInterval = callTimeout) async -> ObservationRun {
        var run = ObservationRun()
        let start = Date()
        guard let rgb = ImageBytes.rgb(from: image, maxPixels: 512) else {
            run.error = "image conversion failed"
            return run
        }
        let deadline = start.addingTimeInterval(timeout)
        do {
            try await engine.load()
            for (attempt, prompt) in [ObservationPrompt.user, ObservationPrompt.retryUser].enumerated() {
                run.attempts = attempt + 1
                let result = try await engine.generate(
                    system: ObservationPrompt.system, user: prompt,
                    image: .init(width: rgb.width, height: rgb.height, bytes: rgb.bytes),
                    grammar: ObservationPrompt.grammar, maxTokens: ObservationPrompt.maxTokens,
                    deadline: deadline
                )
                run.rawOutputs.append(result.text)
                run.prefillSeconds += result.prefillSeconds
                run.generatedTokens += result.generatedTokens
                run.promptTokens = result.promptTokens
                if case .success(let observations) = ObservationParser.parse(result.text) {
                    run.observations = observations
                    run.firstAttemptParsed = attempt == 0
                    break
                }
            }
            if run.observations == nil { run.error = "invalid JSON twice" }
        } catch {
            run.error = "\(error)"
        }
        // Set here, not in a defer: a defer would run after the struct was copied out.
        run.seconds = Date().timeIntervalSince(start)
        return run
    }

    /// The AI dossier arrives in M3; until then callers use the templates.
    func writeDossier(_ input: DossierInput) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: ObservationError.notAvailableYet) }
    }

    func unload() {
        let engine = self.engine
        Task { await engine.unload() }
    }
}
#endif
