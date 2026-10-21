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
        let run = await observeDetailed(image: image, timeout: Self.callTimeout, chaos: false)
        guard let observations = run.observations else { throw ObservationError.invalidOutput }
        return observations
    }

    /// One observation with a single retry on unparseable output (spec 4.1).
    func observeDetailed(image: CGImage, timeout: TimeInterval = callTimeout, chaos: Bool = false) async -> ObservationRun {
        var run = ObservationRun()
        let start = Date()
        guard let rgb = ImageBytes.rgb(from: image, maxPixels: 512) else {
            run.error = "image conversion failed"
            return run
        }
        let deadline = start.addingTimeInterval(timeout)
        do {
            try await engine.load()
            let prompts = chaos ? [ChaosMode.user, ChaosMode.retryUser] : [ObservationPrompt.user, ObservationPrompt.retryUser]
            for (attempt, prompt) in prompts.enumerated() {
                run.attempts = attempt + 1
                let result = try await engine.generate(
                    system: ObservationPrompt.system, user: prompt,
                    image: .init(width: rgb.width, height: rgb.height, bytes: rgb.bytes),
                    grammar: chaos ? ChaosMode.grammar : ObservationPrompt.grammar,
                    maxTokens: chaos ? ChaosMode.maxTokens : ObservationPrompt.maxTokens,
                    temperature: ObservationPrompt.temperature, deadline: deadline
                )
                run.rawOutputs.append(result.text)
                run.prefillSeconds += result.prefillSeconds
                run.generatedTokens += result.generatedTokens
                run.promptTokens = result.promptTokens
                if case .success(let observations) = ObservationParser.parse(result.text) {
                    run.observations = observations
                    run.firstAttemptParsed = attempt == 0
                    if chaos { run.chaosScores = ChaosMode.scores(from: result.text) }
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

    /// M3: Agent K-9's experimental AI field notes ("That top hat? …"),
    /// streamed piece by piece. The caller filters every sentence.
    func writeDossier(_ input: DossierInput) -> AsyncThrowingStream<String, Error> {
        let engine = self.engine
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await engine.load()
                    _ = try await engine.generate(
                        system: DossierPrompt.system, user: DossierPrompt.fieldNotesUser(for: input), image: nil,
                        grammar: DossierPrompt.fieldNotesGrammar, maxTokens: DossierPrompt.fieldNotesMaxTokens,
                        temperature: DossierPrompt.temperature, seed: UInt32(truncatingIfNeeded: input.seed),
                        repeatPenalty: DossierPrompt.repeatPenalty,
                        deadline: Date().addingTimeInterval(Self.callTimeout),
                        onPiece: { piece in
                            continuation.yield(piece)
                            return true
                        }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func unload() {
        let engine = self.engine
        Task { await engine.unload() }
    }
}
#endif
