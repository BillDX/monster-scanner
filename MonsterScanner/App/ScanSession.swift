import MonsterCore
import Observation
import UIKit

/// One scan: the photo, the measurements, the verdict and the dossier.
/// Everything lives in memory and disappears when the session is dropped.
@Observable
final class ScanSession {
    enum Phase: Equatable { case scanning, revealed, noSubject, failed }

    static let minimumScan: Duration = .seconds(5.5)
    static let maximumScan: Duration = .seconds(10)
    static let lineInterval: Duration = .milliseconds(330)

    private(set) var phase: Phase = .scanning
    /// Telemetry lines shown so far.
    private(set) var lines: [String] = []
    /// "Monster probability" gauge, 0...100.
    private(set) var gauge: Double = 0
    private(set) var analysis: ScanAnalysis?
    private(set) var verdict: Verdict?
    private(set) var dossier: Dossier?
    private(set) var calibration = 0
    private(set) var displayImage: UIImage?
    private(set) var isInvisibleVerdict = false

    /// The original photo bytes. Dropped as soon as analysis finishes, so only
    /// the downscaled, metadata-free copy stays in memory.
    @ObservationIgnored private var input: ClassicScanner.Input?
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var gaugeTarget: Double = 64

    init(input: ClassicScanner.Input) {
        self.input = input
    }

    var observations: SubjectObservations { analysis?.evidence.observations ?? .unknown }

    /// Final gauge value: the verdict confidence, or a low reading for humans.
    var finalGauge: Double {
        guard let verdict else { return 0 }
        return verdict.monster == .human ? 100 - verdict.confidence : verdict.confidence
    }

    // MARK: Running

    func run() async {
        phase = .scanning
        lines = []
        gauge = 0
        queue = Array(Telemetry.warmUp.prefix(3))
        guard let input else { phase = .failed; return }

        let work = Task { () -> ScanAnalysis? in
            do {
                return try await ClassicScanner.analyze(input)
            } catch {
                DebugLog.shared.record("Analysis failed: \(error)")
                return nil
            }
        }
        let receiver = Task { [weak self] in
            let result = await work.value
            self?.receive(result)
        }
        await tick(until: { [weak self] in self?.analysisFinished ?? true })
        _ = await receiver.value
    }

    func runSecondOpinion() async {
        guard analysis != nil else { return }
        phase = .scanning
        calibration += 1
        lines = []
        gauge = 10
        queue = ["RECALIBRATING SCANNER…", "CALIBRATION #\(calibration + 1) LOADED", "RE-READING EVIDENCE…"]
        decide()
        gaugeTarget = finalGauge
        if let analysis { queue += Array(Telemetry.lines(for: analysis.evidence).shuffled().prefix(4)) }
        await tick(minimum: .seconds(3), until: { true })
        gauge = finalGauge
        phase = .revealed
    }

    /// "Are they… invisible?" → Ghost verdict.
    func declareInvisible() {
        isInvisibleVerdict = true
        decide()
        gauge = finalGauge
        phase = .revealed
    }

    // MARK: Internals

    @ObservationIgnored private var analysisFinished = false

    private func receive(_ result: ScanAnalysis?) {
        analysisFinished = true
        input = nil
        guard let result else {
            phase = .failed
            queue = []
            return
        }
        analysis = result
        displayImage = UIImage(cgImage: result.photo.displayImage)
        if result.subject == nil {
            queue += ["FACES IN FRAME: 0", "SUBJECT: NOT FOUND", "CHECKING FOR INVISIBILITY…"]
            gaugeTarget = 13
        } else {
            decide()
            gaugeTarget = finalGauge
            queue += Telemetry.lines(for: result.evidence, moonName: result.moonName)
            queue.append("CROSS-REFERENCING CRYPTID DATABASE…")
        }
    }

    /// Feeds telemetry lines and nudges the gauge until the scan is done.
    private func tick(minimum: Duration = ScanSession.minimumScan, until ready: () -> Bool) async {
        let clock = ContinuousClock()
        let start = clock.now
        while !Task.isCancelled {
            if !queue.isEmpty { lines.append(queue.removeFirst()) }
            let step = Double.random(in: 2...9)
            gauge = min(99.9, max(0, gauge + (gauge < gaugeTarget ? step : -step / 2)))

            let elapsed = clock.now - start
            let done = ready() && queue.isEmpty && elapsed >= minimum
            if done || (ready() && elapsed >= Self.maximumScan) { break }
            try? await Task.sleep(for: Self.lineInterval)
        }
        guard phase != .failed else { return }
        if ready() {
            gauge = finalGauge
            if analysis?.subject == nil, !isInvisibleVerdict, analysis != nil {
                phase = .noSubject
            } else if verdict != nil {
                phase = .revealed
            }
        }
    }

    private func decide() {
        guard let analysis else { return }
        let seed = analysis.seed(calibration: calibration)
        let verdict = isInvisibleVerdict
            ? VerdictEngine.invisibleSubject(seed: seed)
            : VerdictEngine.decide(analysis.evidence, seed: seed)
        self.verdict = verdict
        dossier = DossierLibrary.bundled.write(DossierInput(verdict: verdict, observations: analysis.evidence.observations))
    }
}
