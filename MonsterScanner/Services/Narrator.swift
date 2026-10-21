import AVFoundation
import Observation

/// Reads the dossier aloud in a deep "agent" voice (AVSpeechSynthesizer,
/// fully on-device) and reports how far it has got, so the typewriter can
/// keep pace.
@Observable
final class Narrator {
    private(set) var isSpeaking = false
    /// Characters of the current text spoken so far.
    private(set) var spokenCharacters = 0

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let delegate = SpeechDelegate()
    @ObservationIgnored private var currentText = ""

    init() {
        synthesizer.delegate = delegate
        delegate.onProgress = { [weak self] utf16End in self?.progress(utf16End) }
        delegate.onFinish = { [weak self] completed in self?.finished(completed) }
    }

    func speak(_ text: String) {
        stop()
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audio.setActive(true)
        } catch {
            DebugLog.shared.record("Audio session failed: \(error.localizedDescription)")
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.agentVoice
        utterance.pitchMultiplier = 0.72
        utterance.rate = 0.47
        utterance.preUtteranceDelay = 0.25
        currentText = text
        spokenCharacters = 0
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        deactivate()
    }

    private func progress(_ utf16End: Int) {
        let text = currentText
        let index = String.Index(utf16Offset: min(utf16End, text.utf16.count), in: text)
        spokenCharacters = text.distance(from: text.startIndex, to: index)
    }

    private func finished(_ completed: Bool) {
        if completed { spokenCharacters = currentText.count }
        deactivate()
    }

    private func deactivate() {
        guard isSpeaking else { return }
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Prefers an English male voice, en-GB, best quality installed.
    static var agentVoice: AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            if voice.gender == .male { s += 4 }
            if voice.language == "en-GB" { s += 2 }
            if voice.quality == .enhanced { s += 1 }
            if voice.quality == .premium { s += 2 }
            return s
        }
        return english.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

/// Receives speech callbacks (off the main actor) and hops to the main actor.
nonisolated private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    /// Set once on the main actor before speaking starts.
    var onProgress: (@MainActor (Int) -> Void)?
    var onFinish: (@MainActor (Bool) -> Void)?

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let end = characterRange.location + characterRange.length
        let handler = onProgress
        Task { @MainActor in handler?(end) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let handler = onFinish
        Task { @MainActor in handler?(true) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let handler = onFinish
        Task { @MainActor in handler?(false) }
    }
}
