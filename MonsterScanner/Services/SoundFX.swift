import AVFoundation
import MonsterCore
import UIKit

// Sound effects for the scanner, every one of them synthesised in code at
// launch: no audio files, no downloads, no third-party code. The synthesis
// (bottom of this file) is pure and deterministic; the player (middle) just
// schedules the pre-rendered buffers on a small pool of AVAudioPlayerNodes.

// MARK: - Cues

/// Every sound the scanner can make.
nonisolated enum SoundCue: Sendable, Hashable {
    /// Rising sci-fi power-up whoosh, ~0.8 s.
    case scanStart
    /// Very short, quiet telemetry tick (~40 ms) for each scrolling line.
    case blip
    /// Tension roll before the reveal, ~1.2 s.
    case drumroll
    /// The big reveal sting, 1.4-2 s, different for every monster.
    case sting(Monster)
    /// Rubber-stamp THUD, ~0.25 s.
    case stamp
    /// Crackling fire for "Burn the Evidence", ~1.5 s.
    case burn
    /// Short digital glitch for Second Opinion / shake, ~0.4 s.
    case glitch

    /// Every cue, in the order they are pre-rendered.
    static var allCues: [SoundCue] {
        [.blip, .scanStart, .drumroll, .stamp, .glitch, .burn] + Monster.allCases.map { .sting($0) }
    }
}

// MARK: - Player

/// Plays the synthesised cues. Call `prepare()` early (it renders every
/// buffer off the main thread and starts the engine), then `play(_:)` freely:
/// cues overlap on a pool of voices, and blips get a voice of their own so a
/// burst of telemetry never cuts a sting short.
///
/// Fails silently when there is no audio output (Simulator without audio,
/// engine refuses to start). After an interruption, a route or configuration
/// change, a return from the background, or a media-services reset, the
/// engine is restarted (or rebuilt) lazily on the next `play(_:)`.
///
/// Levels: every buffer peaks at -3 dBFS or lower (blips at -20), and the
/// mono voices are mixed at 0.9 into the stereo output (-3 dB pan law), so
/// even a sting and a stamp landing on top of each other stay below 0 dBFS.
@MainActor
final class SoundFX {
    static let shared = SoundFX()

    /// Mirrors the Settings toggle. When false, `play(_:)` does nothing and
    /// anything still sounding is stopped.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue, !isEnabled else { return }
            stopAll()
            if graphReady { engine.pause() }
        }
    }

    private static let voiceCount = 6

    private var engine = AVAudioEngine()
    private var mixer = AVAudioMixerNode()
    private var voices: [AVAudioPlayerNode] = []
    /// Dedicated voice for blips; each new blip interrupts the previous one.
    private var tickVoice = AVAudioPlayerNode()
    /// When each pool voice will be free again (system uptime, seconds).
    private var busyUntil: [TimeInterval] = []
    private var nextVoice = 0
    private var graphReady = false
    private var needsRestart = false
    private var needsRebuild = false
    private var lastStartFailure: TimeInterval?
    private var hasLoggedStartFailure = false

    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1)
    private var buffers: [SoundCue: [AVAudioPCMBuffer]] = [:]
    private var lastVariant: [SoundCue: Int] = [:]
    private var renderTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Renders every buffer (in the background, once), configures the audio
    /// session and starts the engine. Cheap to call again.
    func prepare() {
        observeAudioSystem()
        renderAllInBackground()
        configureSession()
        if isEnabled { _ = ensureRunning() }
    }

    func play(_ cue: SoundCue) {
        guard isEnabled else { return }
        if renderTask == nil { prepare() }
        guard let buffer = buffer(for: cue), ensureRunning() else { return }
        let voice = cue == .blip ? tickVoice : claimVoice(for: buffer)
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        voice.play()
    }

    func stopAll() {
        guard graphReady else { return }
        for voice in voices + [tickVoice] { voice.stop() }
        busyUntil = Array(repeating: 0, count: voices.count)
    }

    /// How long a cue lasts, so callers can time animations to it.
    func duration(of cue: SoundCue) -> TimeInterval {
        SoundSynth.duration(of: cue)
    }

    // MARK: Buffers

    /// Renders off the main thread, installing each cue as soon as it is
    /// ready: the cheap scan sounds come first (a few ms in Release; the
    /// whole set takes ~0.2 s in Release, several seconds in a Debug build).
    private func renderAllInBackground() {
        guard renderTask == nil else { return }
        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            for cue in SoundCue.allCues {
                let variants = SoundSynth.renderVariants(of: cue)
                await self?.install(cue, variants)
            }
        }
    }

    private func install(_ cue: SoundCue, _ variants: [[Float]]) {
        guard let format, buffers[cue] == nil else { return }
        buffers[cue] = variants.compactMap { Self.makeBuffer($0, format: format) }
    }

    private static func makeBuffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        buffer.frameLength = buffer.frameCapacity
        return buffer
    }

    /// A buffer for `cue` (nil while it is still rendering: that cue is
    /// skipped rather than stalling the main thread), picking a different
    /// variant from last time when there are several, so telemetry blips
    /// chatter instead of droning.
    private func buffer(for cue: SoundCue) -> AVAudioPCMBuffer? {
        guard let options = buffers[cue], !options.isEmpty else { return nil }
        var index = Int.random(in: 0..<options.count)
        if options.count > 1, index == lastVariant[cue] { index = (index + 1) % options.count }
        lastVariant[cue] = index
        return options[index]
    }

    /// The first idle pool voice after the last one used, or (when all are
    /// busy) the one that finishes soonest.
    private func claimVoice(for buffer: AVAudioPCMBuffer) -> AVAudioPlayerNode {
        let now = ProcessInfo.processInfo.systemUptime
        let order = (0..<voices.count).map { (nextVoice + $0) % voices.count }
        let index = order.first { busyUntil[$0] <= now }
            ?? order.min { busyUntil[$0] < busyUntil[$1] }
            ?? 0
        nextVoice = (index + 1) % voices.count
        busyUntil[index] = now + Double(buffer.frameLength) / buffer.format.sampleRate
        return voices[index]
    }

    // MARK: Engine

    /// Makes sure the engine is running, (re)building or restarting it if
    /// needed. Retries at most every 2 s after a failure so a stream of
    /// blips on a silent device costs nothing.
    private func ensureRunning() -> Bool {
        if needsRebuild { rebuildGraph() }
        if graphReady, engine.isRunning, !needsRestart { return true }
        let now = ProcessInfo.processInfo.systemUptime
        if let failed = lastStartFailure, now - failed < 2 { return false }

        activateSession()
        guard buildGraphIfNeeded() else { return startFailed(at: now, "no audio output") }
        // Whatever was scheduled died with the old I/O; start the voices afresh.
        stopAll()
        needsRestart = false
        do {
            engine.prepare()
            try engine.start()
            lastStartFailure = nil
            return true
        } catch {
            return startFailed(at: now, error.localizedDescription)
        }
    }

    private func startFailed(at time: TimeInterval, _ reason: String) -> Bool {
        lastStartFailure = time
        if !hasLoggedStartFailure {
            hasLoggedStartFailure = true
            log("SoundFX: engine unavailable (\(reason)); sound effects are off.")
        }
        return false
    }

    private func buildGraphIfNeeded() -> Bool {
        if graphReady { return true }
        guard let format else { return false }
        let output = engine.outputNode.outputFormat(forBus: 0)
        guard output.sampleRate > 0, output.channelCount > 0 else { return false }

        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        mixer.outputVolume = 0.9 // a little headroom when cues overlap
        voices = (0..<Self.voiceCount).map { _ in AVAudioPlayerNode() }
        for voice in voices + [tickVoice] {
            engine.attach(voice)
            engine.connect(voice, to: mixer, format: format)
        }
        busyUntil = Array(repeating: 0, count: voices.count)
        nextVoice = 0
        graphReady = true
        return true
    }

    /// After a media-services reset every node is dead: start from scratch.
    private func rebuildGraph() {
        needsRebuild = false
        if graphReady { engine.stop() }
        engine = AVAudioEngine()
        mixer = AVAudioMixerNode()
        tickVoice = AVAudioPlayerNode()
        voices = []
        busyUntil = []
        graphReady = false
        needsRestart = true
    }

    // MARK: Audio session

    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            log("SoundFX: audio session category failed: \(error.localizedDescription)")
        }
    }

    /// Activates the session, keeping whatever playback mode the narrator set.
    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback { configureSession() }
        do {
            try session.setActive(true)
        } catch {
            log("SoundFX: audio session activation failed: \(error.localizedDescription)")
        }
    }

    private func observeAudioSystem() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] note in
            let changed = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, changed == ObjectIdentifier(self.engine) else { return }
                self.needsRestart = true
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsRestart = true }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsRebuild = true }
        })
        // Back from the background the engine can claim to run with dead I/O.
        observers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsRestart = true }
        })
    }

    private func log(_ message: String) {
        DebugLog.shared.record(message)
        #if DEBUG
        print(message)
        #endif
    }
}

// MARK: - Synthesis

/// Pure, deterministic synthesis of every cue: mono 44.1 kHz Float samples,
/// peak-normalised, with click-free edges. No shared state, so it is safe to
/// call from any thread.
nonisolated enum SoundSynth {
    static let sampleRate = 44_100.0

    /// How many alternative takes a cue has (picked at random when played).
    static func variantCount(of cue: SoundCue) -> Int {
        switch cue {
        case .blip: 4
        case .glitch: 3
        default: 1
        }
    }

    /// Exact length of each rendered cue, in seconds.
    static func duration(of cue: SoundCue) -> Double {
        switch cue {
        case .scanStart: 0.8
        case .blip: 0.04
        case .drumroll: 1.2
        case .stamp: 0.25
        case .burn: 1.5
        case .glitch: 0.4
        case .sting(let monster):
            switch monster {
            case .vampire: 1.9
            case .alien: 1.8
            case .kaiju: 1.8
            case .werewolf: 1.9
            case .zombie: 1.95
            case .robot: 1.4
            case .ghost: 2.0
            case .human: 2.0
            }
        }
    }

    static func renderVariants(of cue: SoundCue) -> [[Float]] {
        (0..<variantCount(of: cue)).map { render(cue, variant: $0) }
    }

    static func render(_ cue: SoundCue, variant: Int = 0) -> [Float] {
        var out = [Double](repeating: 0, count: frames(duration(of: cue)))
        switch cue {
        case .scanStart: scanStart(&out)
        case .blip: blip(&out, variant: variant)
        case .drumroll: drumroll(&out)
        case .stamp: stamp(&out)
        case .burn: burn(&out)
        case .glitch: glitch(&out, variant: variant)
        case .sting(let monster):
            switch monster {
            case .vampire: vampire(&out)
            case .alien: alien(&out)
            case .kaiju: kaiju(&out)
            case .werewolf: werewolf(&out)
            case .zombie: zombie(&out)
            case .robot: robot(&out)
            case .ghost: ghost(&out)
            case .human: sadTrombone(&out)
            }
        }
        return finish(out, peakDB: peakLevel(of: cue))
    }

    /// Peak level (dBFS) per cue, balanced so they sound about equally loud
    /// through a phone speaker: the dense, bright stings sit lower, the
    /// blip far below everything.
    private static func peakLevel(of cue: SoundCue) -> Double {
        switch cue {
        case .blip: -20
        case .glitch: -8
        case .burn: -3.5
        case .sting(.alien), .sting(.werewolf), .sting(.robot): -5.5
        default: -3
        }
    }

    // MARK: Small cues

    /// A soft sine "tick" with a tiny downward chirp. Four pentatonic
    /// pitches (E6 G6 A6 C7) so a run of them sounds like computer chatter.
    private static func blip(_ out: inout [Double], variant: Int) {
        let notes: [Double] = [88, 91, 93, 96]
        let base = hz(notes[variant % notes.count])
        var osc = Phase()
        for i in out.indices {
            let t = time(i)
            let p = osc.advance(base * (1 + 0.08 * exp(-t / 0.003)))
            let env = min(1, t / 0.0015) * exp(-t / 0.010)
            out[i] = env * (sin(2 * .pi * p) + 0.12 * sin(4 * .pi * p))
        }
    }

    /// Resonant saw sweep rising three octaves with a "charging" flutter
    /// that speeds up, a noise whoosh, and a bright "ready" ping at the top.
    private static func scanStart(_ out: inout [Double]) {
        let rise = 0.6
        var saw = Phase(), square = Phase(), sub = Phase(), flutter = Phase(), pingA = Phase(), pingB = Phase()
        var tone = SVF(), air = SVF()
        var cutoffs = (tone: 220.0, air: 350.0)
        var rng = Rng(seed: 11)
        for i in out.indices {
            let t = time(i)
            let p = min(t / rise, 1)
            let f = 80 * pow(2, 3.4 * pow(p, 1.25)) // 80 Hz -> ~850 Hz
            let dt = f / sampleRate
            let osc = 0.55 * Wave.saw(saw.advance(f), dt)
                + 0.35 * Wave.square(square.advance(f * 1.006), dt * 1.006)
                + 0.3 * sin(2 * .pi * sub.advance(f / 2))
            let charge = 0.62 + 0.38 * sin(2 * .pi * flutter.advance(7 + 33 * p * p))
            if i % 16 == 0 { cutoffs = (220 * pow(2, 4.8 * p), 350 * pow(2, 4.2 * p)) } // control rate
            let body = tone.run(osc, cutoffs.tone, q: 3.5).low * charge
            let whoosh = air.run(rng.bipolar(), cutoffs.air, q: 1.4).band
            let swell = t < rise ? 0.12 + 0.88 * pow(p, 1.7) : exp(-(t - rise) / 0.03)
            var sample = swell * (0.8 * body + 0.5 * whoosh * p)
            let pingStart = rise - 0.01
            if t >= pingStart {
                let u = t - pingStart
                let env = min(1, u / 0.002) * exp(-u / 0.06)
                sample += 0.5 * env * (sin(2 * .pi * pingA.advance(1760)) + 0.6 * sin(2 * .pi * pingB.advance(2637)))
            }
            out[i] = sample
        }
    }

    /// Snare roll that speeds up and swells, over a timpani rumble.
    private static func drumroll(_ out: inout [Double]) {
        let length = duration(of: .drumroll)
        var rng = Rng(seed: 21)
        var t = 0.0
        var stroke = 0
        while t < length - 0.02 {
            let progress = t / length
            let hand = stroke.isMultiple(of: 2) ? 1.0 : 0.82
            let amp = (0.22 + 0.78 * pow(progress, 1.4)) * hand * rng.range(0.88, 1.08)
            snare(&out, at: max(0, t + rng.range(-0.002, 0.002)), amp: amp, rng: &rng)
            t += 0.068 - 0.03 * progress // ~15 -> ~26 strokes per second
            stroke += 1
        }
        var a = Phase(), b = Phase(), c = Phase(), tremolo = Phase()
        for i in out.indices {
            let p = time(i) / length
            let roll = 0.75 + 0.25 * sin(2 * .pi * tremolo.advance(17 + 9 * p))
            let drum = sin(2 * .pi * a.advance(98)) + 0.6 * sin(2 * .pi * b.advance(147))
                + 0.35 * sin(2 * .pi * c.advance(196))
            out[i] += 0.22 * pow(p, 1.8) * roll * drum
        }
        highPass(&out, 60)
    }

    private static func snare(_ out: inout [Double], at start: Double, amp: Double, rng: inout Rng) {
        let first = frames(start)
        var rattle = SVF(), body = Phase()
        for j in 0..<frames(0.11) {
            let i = first + j
            guard i < out.count else { break }
            let t = time(j)
            let noise = rattle.run(rng.bipolar(), 3800, q: 0.6).band
            let tone = sin(2 * .pi * body.advance(185 + 60 * exp(-t / 0.01)))
            out[i] += amp * (1.6 * noise * exp(-t / 0.032) + 0.45 * tone * exp(-t / 0.02))
        }
    }

    /// Pitch-dropping thump + rubbery "thock" + woody tock + a crisp click,
    /// saturated together, in a small office.
    private static func stamp(_ out: inout [Double]) {
        var thump = Phase(), tockA = Phase(), tockB = Phase()
        var thockFilter = SVF(), slapFilter = SVF(), clickFilter = SVF()
        var rng = Rng(seed: 31)
        for i in out.indices {
            let t = time(i)
            let w = rng.bipolar()
            let low = sin(2 * .pi * thump.advance(110 + 200 * exp(-t / 0.012))) * exp(-t / 0.06)
            let thock = thockFilter.run(w, 420, q: 1.2).band * exp(-t / 0.04)
            let slap = slapFilter.run(w, 1800, q: 0.8).low * exp(-t / 0.02)
            let tock = (sin(2 * .pi * tockA.advance(340)) + 0.45 * sin(2 * .pi * tockB.advance(910))) * exp(-t / 0.035)
            let click = clickFilter.run(w, 3500, q: 0.7).high * exp(-t / 0.0025)
            out[i] = tanh(2.5 * (0.7 * low + 5 * thock + 1.5 * slap + 1.1 * tock + 0.3 * click))
        }
        highPass(&out, 50)
        reverb(&out, wet: 0.1, room: 0.6, damp: 0.5)
    }

    /// "FWOOMP" ignition, a flickering roar, and crackles that get busier
    /// as the evidence catches, dying down at the end.
    private static func burn(_ out: inout [Double]) {
        let length = duration(of: .burn)
        var rng = Rng(seed: 41)
        var roarFilter = SVF(), igniteFilter = SVF(), hissFilter = SVF()
        var brown = 0.0, flicker = 0.7, flickerTarget = 0.7
        for i in out.indices {
            let t = time(i)
            let w = rng.bipolar()
            brown = 0.985 * brown + 0.15 * w
            if i % 441 == 0 { flickerTarget = rng.range(0.55, 1.0) }
            flicker += (flickerTarget - flicker) * 0.002
            let flare = 180 + 2600 * min(t / 0.22, 1) * exp(-max(t - 0.22, 0) / 0.25)
            let ignite = igniteFilter.run(w, flare, q: 0.9).low * min(1, t / 0.03) * exp(-t / 0.35)
            let roar = (0.5 * roarFilter.run(w, 900, q: 0.5).band + 0.5 * brown) * flicker
            let hiss = hissFilter.run(w, 5000, q: 0.7).high
            out[i] = 1.4 * ignite + min(1, t / 0.12) * (0.6 * roar + 0.06 * hiss)
        }
        var t = 0.08
        while t < length - 0.05 {
            let big = rng.unit() < 0.12
            crackle(
                &out, at: t,
                amp: big ? rng.range(0.4, 0.7) : rng.range(0.1, 0.4),
                freq: big ? rng.range(500, 1200) : rng.range(1800, 6500),
                decay: big ? rng.range(0.006, 0.014) : rng.range(0.0008, 0.003),
                rng: &rng
            )
            let rate = 25 + 50 * min(t / 0.5, 1) // crackles per second
            t += -log(max(rng.unit(), 1e-6)) / rate
        }
        highPass(&out, 60)
        fadeOut(&out, seconds: 0.4)
    }

    private static func crackle(
        _ out: inout [Double], at start: Double, amp: Double, freq: Double, decay: Double, rng: inout Rng
    ) {
        let first = frames(start)
        var filter = SVF()
        for j in 0..<frames(decay * 6) {
            let i = first + j
            guard i < out.count else { break }
            out[i] += 2.5 * amp * filter.run(rng.bipolar(), freq, q: 1.5).band * exp(-time(j) / decay)
        }
    }

    /// Corrupted-data stutter: crushed square blips, repeated slivers,
    /// sample-and-hold noise, dropouts and modem-ish FM, all at 4 bits.
    private static func glitch(_ out: inout [Double], variant: Int) {
        var rng = Rng(seed: 51 &+ UInt64(variant) &* 7919)
        var position = 0
        var previous: [Double] = []
        var chunkIndex = 0
        while position < out.count {
            var length = frames(rng.range(0.014, 0.05))
            var chunk = [Double](repeating: 0, count: length)
            switch chunkIndex == 0 ? 0 : Int(rng.unit() * 6) {
            case 0, 1:
                let from = rng.range(180, 2400)
                let to = rng.unit() < 0.4 ? from * rng.range(0.2, 0.6) : from
                var osc = Phase()
                for j in chunk.indices {
                    let f = from + (to - from) * Double(j) / Double(length)
                    chunk[j] = 0.8 * Wave.square(osc.advance(f), f / sampleRate, duty: 0.3)
                }
            case 2 where !previous.isEmpty:
                let sliver = max(1, min(previous.count, frames(rng.range(0.004, 0.012))))
                for j in chunk.indices { chunk[j] = previous[j % sliver] }
            case 3:
                let hold = Int(rng.range(2, 24))
                var value = 0.0
                for j in chunk.indices {
                    if j % hold == 0 { value = rng.bipolar() }
                    chunk[j] = 0.7 * value
                }
            case 4:
                length = frames(rng.range(0.004, 0.018))
                chunk = [Double](repeating: 0, count: length)
            default:
                var carrier = Phase(), modulator = Phase()
                let fc = rng.range(600, 3000), fm = rng.range(30, 300)
                for j in chunk.indices {
                    let m = sin(2 * .pi * modulator.advance(fm))
                    chunk[j] = sin(2 * .pi * carrier.advance(fc * (1 + 0.6 * m)))
                }
            }
            let ramp = min(frames(0.0005), chunk.count / 2)
            for j in chunk.indices {
                var v = (chunk[j] * 8).rounded() / 8
                if j < ramp { v *= Double(j) / Double(ramp) }
                if j >= chunk.count - ramp { v *= Double(chunk.count - 1 - j) / Double(ramp) }
                chunk[j] = v
            }
            for j in chunk.indices where position + j < out.count {
                out[position + j] = chunk[j] * (1 - 0.45 * time(position + j) / 0.4)
            }
            previous = chunk
            position += max(chunk.count, 1)
            chunkIndex += 1
        }
    }

    // MARK: Stings

    /// Pipe organ: an A-G-A mordent in octaves, then a diminished chord over
    /// a low D pedal that "resolves" into a huge D minor, in a cathedral.
    private static func vampire(_ out: inout [Double]) {
        // Drawbars 16', 8', 5 1/3', 4', 2 2/3', 2', 1' as harmonics of the 16' pitch.
        let organ = Wavetable([(1, 0.4), (2, 1.0), (3, 0.55), (4, 0.7), (6, 0.4), (8, 0.42), (16, 0.15)])
        var rng = Rng(seed: 61)
        let mordent: [(start: Double, length: Double, midi: Double)] = [(0, 0.1, 69), (0.1, 0.09, 67), (0.19, 0.3, 69)]
        for note in mordent {
            for midi in [note.midi, note.midi - 12] {
                organNote(&out, organ, midi: midi, start: note.start, length: note.length, amp: 0.22, rng: &rng)
            }
        }
        // Low D pedal under C#3 E3 G3 Bb3 C#4 E4 G4 ...
        organNote(&out, organ, midi: 38, start: 0.52, length: 1.08, amp: 0.09, rng: &rng)
        for midi in [49.0, 52, 55, 58, 61, 64, 67] {
            organNote(&out, organ, midi: midi, start: 0.52, length: 0.36, amp: 0.13, rng: &rng)
        }
        // ... resolving to D3 F3 A3 D4 F4 A4.
        for midi in [50.0, 53, 57, 62, 65, 69] {
            organNote(&out, organ, midi: midi, start: 0.9, length: 0.7, amp: 0.15, rng: &rng)
        }
        highPass(&out, 70)
        saturate(&out, drive: 2) // a little valve-amp growl, and much louder on a phone
        reverb(&out, wet: 0.32, room: 0.86, damp: 0.35)
        fadeOut(&out, seconds: 0.2)
    }

    private static func organNote(
        _ out: inout [Double], _ table: Wavetable, midi: Double, start: Double, length: Double,
        amp: Double, rng: inout Rng
    ) {
        let f = hz(midi)
        let first = frames(start)
        var rankA = Phase(), rankB = Phase(), tremulant = Phase(), chiff = SVF()
        rankB.value = rng.unit()
        for j in 0..<frames(length + 0.25) {
            let i = first + j
            guard i < out.count else { break }
            let t = time(j)
            let attack = min(1, t / 0.018)
            let env = t < length ? attack : attack * exp(-(t - length) / 0.05)
            let trem = sin(2 * .pi * tremulant.advance(5.6))
            let wobble = 1 + 0.0012 * trem
            // The 16' fundamental is an octave below the written note.
            let pipes = table.at(rankA.advance(f * wobble / 2)) + 0.7 * table.at(rankB.advance(f * wobble * 1.0018 / 2))
            // Breathy "chiff" as the pipe speaks (gone after ~0.1 s).
            let puff = t < 0.1 ? 0.5 * chiff.run(rng.bipolar(), f * 3, q: 2).band * exp(-t / 0.015) : 0
            out[i] += amp * env * (pipes * (1 + 0.06 * trem) + puff)
        }
    }

    /// Theremin swooping around with ever-wobblier vibrato over a pulsing
    /// flying-saucer hum, with a spacey echo.
    private static func alien(_ out: inout [Double]) {
        let length = duration(of: .sting(.alien))
        let pitch = Curve([(0, 70), (0.28, 79), (0.55, 73), (0.92, 84), (1.25, 76), (1.55, 81), (1.8, 78)])
        var voice = Phase(), vibrato = Phase(), wobble = Phase(), humA = Phase(), humB = Phase(), pulse = Phase()
        for i in out.indices {
            let t = time(i)
            let depth = 0.18 + 0.5 * min(t / 1.2, 1)
            let midi = pitch(t) + depth * sin(2 * .pi * vibrato.advance(6.3)) + 0.35 * sin(2 * .pi * wobble.advance(1.7))
            let p = voice.advance(hz(midi))
            let theremin = sin(2 * .pi * p) + 0.12 * sin(4 * .pi * p) + 0.05 * sin(6 * .pi * p)
            let amp = min(1, t / 0.09) * max(0, min(1, (length - 0.1 - t) / 0.35))
            let hum = (Wave.triangle(humA.advance(130.8)) + Wave.triangle(humB.advance(196.9)))
                * (0.55 + 0.45 * sin(2 * .pi * pulse.advance(7.5)))
            out[i] = amp * (0.75 * theremin + 0.16 * hum)
        }
        echo(&out, delay: 0.17, feedback: 0.35, wet: 0.35)
        fadeOut(&out, seconds: 0.15)
    }

    /// Two enormous stomps (the second bigger), then the windows rattle.
    private static func kaiju(_ out: inout [Double]) {
        var rng = Rng(seed: 81)
        stomp(&out, at: 0, size: 1.0, rng: &rng)
        stomp(&out, at: 0.62, size: 1.25, rng: &rng)
        var rattle = SVF(), shake = Phase()
        let start = 0.66
        for i in frames(start)..<out.count {
            let t = time(i) - start
            let r = rattle.run(rng.bipolar(), 2200, q: 3).band * max(0, sin(2 * .pi * shake.advance(23)))
            out[i] += 0.5 * r * exp(-t / 0.18)
        }
        highPass(&out, 45)
        saturate(&out, drive: 1.8)
        echo(&out, delay: 0.11, feedback: 0.3, wet: 0.25) // bouncing off the skyscrapers
        fadeOut(&out, seconds: 0.3)
    }

    private static func stomp(_ out: inout [Double], at start: Double, size: Double, rng: inout Rng) {
        let first = frames(start)
        var body = Phase(), chest = Phase(), crunch = SVF(), rumble = SVF()
        var brown = 0.0
        for i in first..<out.count {
            let t = time(i - first)
            let f = (50 + 150 * exp(-t / 0.05)) / size
            let boom = sin(2 * .pi * body.advance(f)) * exp(-t / (0.3 * size))
            // Phone speakers have no real bass: the mid "chest" thump, the
            // crunch and the hard saturation are what make it huge on one.
            let thump = sin(2 * .pi * chest.advance((140 + 160 * exp(-t / 0.04)) / size)) * exp(-t / 0.15)
            let w = rng.bipolar()
            brown = 0.99 * brown + 0.1 * w
            let debris = crunch.run(w, 600 + 2400 * exp(-t / 0.08), q: 0.9).low * exp(-t / 0.25)
            let ground = rumble.run(brown, 260, q: 0.8).low * exp(-t / 0.5)
            out[i] += size * tanh(3 * (0.6 * boom + 1.2 * thump + 3 * debris + ground))
        }
        // Rubble pattering down afterwards.
        var t = start + 0.05
        while t < min(start + 0.55, duration(of: .sting(.kaiju)) - 0.05) {
            let fade = 1 - (t - start) / 0.55
            crackle(&out, at: t, amp: size * fade * rng.range(0.15, 0.45), freq: rng.range(600, 2500),
                    decay: rng.range(0.003, 0.008), rng: &rng)
            t += -log(max(rng.unit(), 1e-6)) / 35
        }
    }

    /// "A-WOOOOO": a howl that rises, holds with growing vibrato and falls,
    /// answered by a second wolf further away.
    private static func werewolf(_ out: inout [Double]) {
        howl(
            &out, start: 0, length: 1.75, amp: 1, seed: 91,
            contour: Curve([(0, 290), (0.2, 540), (0.45, 640), (1.05, 665), (1.45, 520), (1.75, 340)])
        )
        howl(
            &out, start: 0.55, length: 1.3, amp: 0.3, seed: 92,
            contour: Curve([(0, 420), (0.2, 760), (0.7, 800), (1.05, 640), (1.3, 470)])
        )
        reverb(&out, wet: 0.28, room: 0.82, damp: 0.4)
        fadeOut(&out, seconds: 0.2)
    }

    private static func howl(
        _ out: inout [Double], start: Double, length: Double, amp: Double, seed: UInt64, contour: Curve
    ) {
        var rng = Rng(seed: seed)
        var voice = Phase(), vibrato = Phase(), formant1 = SVF(), formant2 = SVF(), breath = SVF()
        var base = 0.0, open = 0.0, env = 0.0
        let first = frames(start)
        for j in 0..<frames(length) {
            let i = first + j
            guard i < out.count else { break }
            let t = time(j)
            if j % 32 == 0 { // control rate
                base = contour(t)
                open = exp(-t / 0.25) // the mouth starts open ("a") and rounds into "oo"
                env = min(1, t / 0.12) * max(0, min(1, (length - t) / 0.4)) * (0.75 + 0.25 * min(1, t / 0.5))
            }
            let depth = 0.012 * min(1, max(0, (t - 0.35) / 0.6))
            let f = base * (1 + depth * sin(2 * .pi * vibrato.advance(5.2)))
            let p = voice.advance(f)
            let pure = sin(2 * .pi * p) + 0.3 * sin(4 * .pi * p) + 0.1 * sin(6 * .pi * p)
            let buzz = Wave.saw(p, f / sampleRate)
            let vowel = formant1.run(buzz, 350 + 450 * open, q: 5).band + 0.6 * formant2.run(buzz, 800 + 400 * open, q: 6).band
            let air = breath.run(rng.bipolar(), base * 2, q: 4).band
            out[i] += amp * env * (0.8 * pure + 0.35 * vowel + 0.06 * air)
        }
    }

    /// A slow, wobbling, creaky groan whose vowels drift through
    /// "uuuh... b-r-aaai-nnn-zzz".
    private static func zombie(_ out: inout [Double]) {
        let length = duration(of: .sting(.zombie))
        let times: [Double] = [0, 0.5, 0.58, 0.64, 0.74, 1.2, 1.42, 1.55, 1.7, 1.95]
        let f1 = Curve(times, [450, 480, 300, 420, 760, 740, 320, 260, 280, 280])
        let f2 = Curve(times, [850, 900, 700, 1050, 1150, 1200, 2000, 1700, 1600, 1600])
        let f3 = Curve(times, [2300, 2300, 2200, 1450, 2400, 2500, 2700, 2600, 2600, 2600])
        let voicing = Curve(times, [0.15, 0.9, 0.2, 0.75, 1, 1, 0.95, 0.55, 0.35, 0])
        let buzzing = Curve(times, [0, 0, 0, 0, 0, 0, 0, 0.1, 0.9, 0.5])
        var rng = Rng(seed: 71)
        var glottis = Phase(), wobble = Phase()
        var formant1 = SVF(), formant2 = SVF(), formant3 = SVF(), growl = SVF(), fricative = SVF()
        var creak = 1.0, creakTarget = 1.0, jitter = 0.0
        var formants = (f1: 0.0, f2: 0.0, f3: 0.0, voice: 0.0, buzz: 0.0)
        for i in out.indices {
            let t = time(i)
            if i % 32 == 0 { formants = (f1(t), f2(t), f3(t), voicing(t), buzzing(t)) } // control rate
            if i % 1300 == 0 { creakTarget = rng.range(0.45, 1) }
            creak += (creakTarget - creak) * 0.004
            jitter += (rng.bipolar() * 0.4 - jitter) * 0.001
            let semis = 1.1 * sin(2 * .pi * wobble.advance(2.6)) + jitter
            let f = (96 - 14 * t / length) * pow(2, semis / 12)
            let dt = f / sampleRate
            let p = glottis.advance(f)
            let source = Wave.saw(p, dt) + 0.4 * Wave.square(p, dt, duty: 0.3)
            let vowel = 3 * formant1.run(source, formants.f1, q: formants.f1 / 90).band
                + 2.4 * formant2.run(source, formants.f2, q: formants.f2 / 110).band
                + 1.2 * formant3.run(source, formants.f3, q: formants.f3 / 160).band
            let throat = 0.25 * growl.run(source, 400, q: 0.7).low
            let zz = fricative.run(rng.bipolar(), 3500, q: 0.7).high * (0.6 + 0.4 * Wave.saw(p, dt))
            let voice = formants.voice * creak * (vowel + throat) + 0.25 * formants.buzz * zz
            out[i] = tanh(2.2 * voice)
        }
        highPass(&out, 60)
        fadeOut(&out, seconds: 0.08)
    }

    /// Fast square-wave bleep-bloop arpeggio, then a final "bee-boop",
    /// crushed to retro bits with a short echo.
    private static func robot(_ out: inout [Double]) {
        let arpeggio: [Double] = [72, 76, 79, 84, 88, 84, 79, 91, 72, 79, 76, 96]
        var notes: [(start: Double, length: Double, from: Double, to: Double)] = []
        var t = 0.0
        for (k, midi) in arpeggio.enumerated() {
            let slide = k % 4 == 3 ? -7.0 : 0 // every fourth note is a "bloop"
            notes.append((t, 0.06, midi, midi + slide))
            t += 0.068
        }
        notes.append((t + 0.04, 0.13, 96, 96))
        notes.append((t + 0.22, 0.32, 79, 72))
        for (k, note) in notes.enumerated() {
            beep(&out, start: note.start, length: note.length, from: note.from, to: note.to, duty: k.isMultiple(of: 2) ? 0.5 : 0.25)
        }
        bitcrush(&out, levels: 32, hold: 2)
        echo(&out, delay: 0.095, feedback: 0.28, wet: 0.22)
        fadeOut(&out, seconds: 0.1)
    }

    private static func beep(_ out: inout [Double], start: Double, length: Double, from: Double, to: Double, duty: Double) {
        let first = frames(start)
        var osc = Phase()
        for j in 0..<frames(length) {
            let i = first + j
            guard i < out.count else { break }
            let t = time(j)
            let f = hz(from + (to - from) * min(1, t / (length * 0.8)))
            let env = min(1, t / 0.003) * min(1, max(0, (length - t) / 0.008))
            out[i] += 0.5 * env * Wave.square(osc.advance(f), f / sampleRate, duty: duty)
        }
    }

    /// Airy "ooOOOooo": a breathy, vibrato-laden voice with a detuned
    /// octave below, swelling and fading in a huge reverb.
    private static func ghost(_ out: inout [Double]) {
        let length = duration(of: .sting(.ghost))
        let pitch = Curve([(0, 67), (0.5, 72), (1.0, 76), (1.45, 71), (2.0, 64)])
        var lead = Phase(), under = Phase(), vibrato = Phase()
        var breathA = SVF(), breathB = SVF(), air = SVF()
        var rng = Rng(seed: 75)
        var swell = 0.0, note = 0.0
        for i in out.indices {
            let t = time(i)
            if i % 32 == 0 { // control rate
                swell = pow(sin(.pi * min(t / length, 1)), 1.3)
                note = pitch(t)
            }
            let midi = note + 0.45 * sin(2 * .pi * vibrato.advance(5 + 0.6 * t / length))
            let f = hz(midi)
            let p = lead.advance(f)
            let tone = sin(2 * .pi * p) + 0.18 * sin(4 * .pi * p) + 0.35 * sin(2 * .pi * under.advance(f * 0.4995))
            let w = rng.bipolar()
            let breathy = breathA.run(w, hz(note), q: 6).band + 0.6 * breathB.run(w, 800, q: 4).band
            let hiss = air.run(w, 6000, q: 0.7).high
            out[i] = swell * (0.6 * tone + 0.9 * breathy + 0.04 * hiss)
        }
        reverb(&out, wet: 0.45, room: 0.9, damp: 0.25)
        fadeOut(&out, seconds: 0.25)
    }

    /// The sad trombone: "wah, wah, wah, waaaaah". Four descending
    /// semitones (Bb3 A3 Ab3 G3) on a plunger-muted brass voice; the last
    /// note wobbles with an over-the-top vibrato and sags flat as it dies.
    private static func sadTrombone(_ out: inout [Double]) {
        var rng = Rng(seed: 101)
        let notes: [Double] = [58, 57, 56, 55]
        for (k, midi) in notes.enumerated() {
            let last = k == notes.count - 1
            tromboneNote(&out, midi: midi, start: 0.3 * Double(k), length: last ? 0.98 : 0.25, wobble: last, rng: &rng)
        }
        reverb(&out, wet: 0.1, room: 0.7, damp: 0.5)
        fadeOut(&out, seconds: 0.08)
    }

    private static func tromboneNote(
        _ out: inout [Double], midi: Double, start: Double, length: Double, wobble: Bool, rng: inout Rng
    ) {
        let first = frames(start)
        var osc = Phase(), vibrato = Phase(), mute = SVF(), puff = SVF()
        var cutoff = 350.0
        for j in 0..<frames(length + 0.1) {
            let i = first + j
            guard i < out.count else { break }
            let t = time(j)
            var m = midi - 0.45 * exp(-t / 0.03) // lip "scoop" up into the note
            let mute0to1: Double // plunger: 0 closed ... 1 open
            if wobble {
                let depth = 0.55 * min(1, max(0, (t - 0.18) / 0.35))
                let v = sin(2 * .pi * vibrato.advance(5.2 - 1.2 * t / length))
                let sag = 0.9 * pow(max(0, (t - 0.45) / (length - 0.45)), 2)
                m += depth * v - sag
                let closing = 1 - 0.6 * min(1, max(0, (t - 0.6) / 0.4))
                mute0to1 = min(1, t / 0.09) * (0.65 + 0.35 * v * min(1, depth / 0.3)) * closing
            } else {
                mute0to1 = min(1, t / 0.08) * (1 - 0.45 * min(1, max(0, (t - 0.1) / 0.15)))
            }
            let f = hz(m)
            let dt = f / sampleRate
            let p = osc.advance(f)
            let brass = Wave.saw(p, dt) + 0.25 * Wave.square(p, dt)
            let amp = t < length
                ? min(1, t / 0.035) * (0.85 + 0.15 * exp(-t / 0.08))
                : exp(-(t - length) / 0.018)
            if j % 16 == 0 { cutoff = 350 + 2100 * mute0to1 * (0.6 + 0.4 * amp) } // control rate
            let tone = mute.run(brass, cutoff, q: 2.2).low
            let breath = 0.3 * puff.run(rng.bipolar(), 1400, q: 1).band * exp(-t / 0.02)
            out[i] += amp * tanh(1.4 * (tone + breath))
        }
    }

    // MARK: Effects

    /// Freeverb-style mono reverb (8 damped combs into 4 allpasses), in place.
    private static func reverb(_ x: inout [Double], wet: Double, room: Double, damp: Double) {
        // 8 combs then 4 allpasses. Raw pointers keep this fast even in
        // unoptimised Debug builds (where Array subscripts are slow).
        let lengths = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617, 556, 441, 341, 225]
        let lineCount = lengths.count, combCount = 8, total = lengths.reduce(0, +)
        let lines = UnsafeMutablePointer<Double>.allocate(capacity: total)
        let cursors = UnsafeMutablePointer<UnsafeMutablePointer<Double>>.allocate(capacity: lineCount)
        let starts = UnsafeMutablePointer<UnsafeMutablePointer<Double>>.allocate(capacity: lineCount)
        let ends = UnsafeMutablePointer<UnsafeMutablePointer<Double>>.allocate(capacity: lineCount)
        let lows = UnsafeMutablePointer<Double>.allocate(capacity: combCount)
        defer {
            lines.deallocate()
            cursors.deallocate()
            starts.deallocate()
            ends.deallocate()
            lows.deallocate()
        }
        lines.initialize(repeating: 0, count: total)
        lows.initialize(repeating: 0, count: combCount)
        var offset = 0
        for d in 0..<lineCount {
            (starts + d).initialize(to: lines + offset)
            (cursors + d).initialize(to: lines + offset)
            offset += lengths[d]
            (ends + d).initialize(to: lines + offset)
        }
        let count = x.count
        x.withUnsafeMutableBufferPointer { signal in
            guard let s = signal.baseAddress else { return }
            for i in 0..<count {
                let input = s[i] * 0.015
                var sum = 0.0
                for d in 0..<lineCount {
                    let slot = cursors[d]
                    let y = slot.pointee
                    if d < combCount {
                        lows[d] = y * (1 - damp) + lows[d] * damp
                        slot.pointee = input + lows[d] * room
                        sum += y
                    } else {
                        slot.pointee = sum + y * 0.5
                        sum = y - sum
                    }
                    let next = slot + 1
                    cursors[d] = next == ends[d] ? starts[d] : next
                }
                s[i] += 3 * wet * sum
            }
        }
    }

    /// Feedback delay with a darkening loop, in place.
    private static func echo(_ x: inout [Double], delay: Double, feedback: Double, wet: Double) {
        var line = [Double](repeating: 0, count: max(1, frames(delay)))
        var index = 0
        var tone = OnePole()
        for i in x.indices {
            let delayed = line[index]
            line[index] = x[i] + tone.low(delayed, 3000) * feedback
            index = (index + 1) % line.count
            x[i] += delayed * wet
        }
    }

    /// Quantise to `levels` steps per unit and sample-and-hold every `hold` frames.
    private static func bitcrush(_ x: inout [Double], levels: Double, hold: Int) {
        var held = 0.0
        for i in x.indices {
            if i % hold == 0 { held = (x[i] * levels).rounded() / levels }
            x[i] = held
        }
    }

    /// 12 dB/octave high-pass, in place: drops sub-bass a phone speaker
    /// cannot play anyway, so it stops eating the headroom.
    private static func highPass(_ x: inout [Double], _ cutoff: Double) {
        var filter = SVF()
        for i in x.indices { x[i] = filter.run(x[i], cutoff).high }
    }

    /// Normalises to a peak of 1, then soft-clips with tanh: thickens the
    /// sound and lowers its crest factor (so it is louder at the same peak).
    private static func saturate(_ x: inout [Double], drive: Double) {
        let peak = x.reduce(0) { max($0, abs($1)) }
        guard peak > 1e-9 else { return }
        for i in x.indices { x[i] = tanh(drive * x[i] / peak) }
    }

    private static func fadeOut(_ x: inout [Double], seconds: Double) {
        let n = min(frames(seconds), x.count)
        guard n > 0 else { return }
        for k in 0..<n {
            x[x.count - n + k] *= 0.5 + 0.5 * cos(.pi * Double(k + 1) / Double(n))
        }
    }

    /// NaN guard, DC removal, click-free edges and peak normalisation.
    private static func finish(_ x: [Double], peakDB: Double) -> [Float] {
        var y = x.map { $0.isFinite ? $0 : 0 }
        var previousIn = 0.0, previousOut = 0.0
        for i in y.indices {
            let value = y[i] - previousIn + 0.9985 * previousOut
            previousIn = y[i]
            previousOut = value
            y[i] = value
        }
        let n = y.count
        let fadeIn = min(frames(0.0015), n / 4)
        for i in 0..<fadeIn { y[i] *= 0.5 - 0.5 * cos(.pi * Double(i) / Double(fadeIn)) }
        let fadeOutFrames = min(frames(0.012), n / 4)
        for i in 0..<fadeOutFrames { y[n - 1 - i] *= 0.5 - 0.5 * cos(.pi * Double(i) / Double(fadeOutFrames)) }
        let peak = y.reduce(0) { max($0, abs($1)) }
        guard peak > 1e-9 else { return [Float](repeating: 0, count: n) }
        let gain = pow(10, peakDB / 20) / peak
        return y.map { Float($0 * gain) }
    }

    // MARK: Helpers

    static func frames(_ seconds: Double) -> Int {
        max(0, Int((seconds * sampleRate).rounded()))
    }

    private static func time(_ frame: Int) -> Double {
        Double(frame) / sampleRate
    }

    private static func hz(_ midi: Double) -> Double {
        440 * pow(2, (midi - 69) / 12)
    }
}

/// Phase accumulator in cycles, 0..<1.
private nonisolated struct Phase {
    var value = 0.0

    /// Returns the current phase, then advances it by one frame at `hz`.
    mutating func advance(_ hz: Double) -> Double {
        let current = value
        value += hz / SoundSynth.sampleRate
        value -= value.rounded(.down)
        return current
    }
}

/// Waveforms of a phase in cycles; saw and square are polyBLEP band-limited.
private nonisolated enum Wave {
    static func triangle(_ p: Double) -> Double { 1 - 4 * abs(p - 0.5) }

    static func saw(_ p: Double, _ dt: Double) -> Double { 2 * p - 1 - blep(p, dt) }

    static func square(_ p: Double, _ dt: Double, duty: Double = 0.5) -> Double {
        var value = p < duty ? 1.0 : -1.0
        value += blep(p, dt)
        var falling = p - duty
        if falling < 0 { falling += 1 }
        value -= blep(falling, dt)
        return value
    }

    private static func blep(_ t: Double, _ dt: Double) -> Double {
        guard dt > 0 else { return 0 }
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        }
        if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }
}

/// Topology-preserving state-variable filter: stable under fast sweeps.
/// `band` is normalised to unity gain at the centre frequency.
private nonisolated struct SVF {
    private var ic1 = 0.0
    private var ic2 = 0.0
    private var cutoff = -1.0
    private var q = -1.0
    private var k = 0.0, a1 = 0.0, a2 = 0.0, a3 = 0.0

    mutating func run(_ x: Double, _ cutoff: Double, q: Double = 0.707) -> (low: Double, band: Double, high: Double) {
        if cutoff != self.cutoff || q != self.q { // coefficients only when they change
            self.cutoff = cutoff
            self.q = q
            let fc = min(max(cutoff, 10), SoundSynth.sampleRate * 0.45)
            let g = tan(.pi * fc / SoundSynth.sampleRate)
            k = 1 / max(q, 0.05)
            a1 = 1 / (1 + g * (g + k))
            a2 = g * a1
            a3 = g * a2
        }
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return (v2, k * v1, x - k * v1 - v2)
    }
}

private nonisolated struct OnePole {
    private var y = 0.0

    mutating func low(_ x: Double, _ cutoff: Double) -> Double {
        y += (1 - exp(-2 * .pi * cutoff / SoundSynth.sampleRate)) * (x - y)
        return y
    }
}

/// One cycle of a sum of harmonics, read with linear interpolation.
private nonisolated struct Wavetable {
    private let table: [Double]

    init(_ harmonics: [(Int, Double)], size: Int = 2048) {
        var table = (0...size).map { i in
            let p = Double(i) / Double(size)
            return harmonics.reduce(0.0) { $0 + $1.1 * sin(2 * .pi * Double($1.0) * p) }
        }
        let peak = table.reduce(0) { max($0, abs($1)) }
        if peak > 0 { table = table.map { $0 / peak } }
        self.table = table
    }

    func at(_ phase: Double) -> Double {
        let x = phase * Double(table.count - 1)
        let i = min(Int(x), table.count - 2)
        return table[i] + (table[i + 1] - table[i]) * (x - Double(i))
    }
}

/// Keyframed value with smoothstep easing between points (held at the ends).
private nonisolated struct Curve {
    private let times: [Double]
    private let values: [Double]

    init(_ points: [(Double, Double)]) {
        times = points.map { $0.0 }
        values = points.map { $0.1 }
    }

    init(_ times: [Double], _ values: [Double]) {
        self.times = times
        self.values = values
    }

    func callAsFunction(_ t: Double) -> Double {
        guard let first = times.first, let last = times.last, values.count == times.count else { return 0 }
        if t <= first { return values[0] }
        if t >= last { return values[values.count - 1] }
        var k = 1
        while times[k] < t { k += 1 }
        let u = (t - times[k - 1]) / (times[k] - times[k - 1])
        return values[k - 1] + (values[k] - values[k - 1]) * u * u * (3 - 2 * u)
    }
}

/// Small deterministic xorshift generator, so every render is identical.
private nonisolated struct Rng {
    private var state: UInt64

    init(seed: UInt64) {
        state = (seed &+ 0x9E37_79B9_7F4A_7C15) &* 0xBF58_476D_1CE4_E5B9
        if state == 0 { state = 1 }
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) * 0x1p-53 }

    /// Uniform in -1..<1.
    mutating func bipolar() -> Double { unit() * 2 - 1 }

    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }
}
