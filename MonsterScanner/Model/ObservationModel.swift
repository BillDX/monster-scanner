import CoreGraphics
import Foundation
import MonsterCore

/// A vision-language model that describes the subject and writes dossiers
/// (spec section 2). Runtimes are swappable behind this protocol. It never
/// decides the verdict: that's `VerdictEngine`.
nonisolated protocol ObservationModel: AnyObject, Sendable {
    /// Short name for telemetry and the readout, e.g. "QWEN3-VL-2B".
    var displayName: String { get }
    func prewarm() async throws
    func observe(image: CGImage) async throws -> SubjectObservations
    /// Like `observe`, but never throws and reports timings and attempts.
    /// With `chaos`, the model also scores every monster (spec 4.2b).
    func observeDetailed(image: CGImage, timeout: TimeInterval, chaos: Bool) async -> ObservationRun
    func writeDossier(_ input: DossierInput) -> AsyncThrowingStream<String, Error>
    func unload()
}

/// Details of one observation call, for telemetry, the debug screen and the
/// benchmark.
nonisolated struct ObservationRun: Sendable {
    var observations: SubjectObservations?
    var attempts = 0
    var firstAttemptParsed = false
    var rawOutputs: [String] = []
    var seconds = 0.0
    var prefillSeconds = 0.0
    var generatedTokens = 0
    var promptTokens = 0
    var error: String?
    /// Chaos Mode only: the AI's 0-100 score per monster.
    var chaosScores: [Monster: Int]?
}

nonisolated enum ObservationError: Error, Equatable {
    case invalidOutput
    case imageConversionFailed
    case notAvailableYet
}

nonisolated extension ObservationModel {
    func observeDetailed(image: CGImage, timeout: TimeInterval, chaos: Bool) async -> ObservationRun {
        var run = ObservationRun()
        let start = Date()
        do {
            run.observations = try await observe(image: image)
            run.attempts = 1
            run.firstAttemptParsed = true
        } catch {
            run.error = "\(error)"
        }
        run.seconds = Date().timeIntervalSince(start)
        return run
    }
}
