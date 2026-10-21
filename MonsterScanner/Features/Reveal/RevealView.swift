import MonsterCore
import SwiftUI

/// The big reveal: blackout + haptic spike, verdict card, narrated dossier,
/// readings and the clues behind the verdict.
struct RevealView: View {
    let session: ScanSession
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    /// Bumps on every reveal so the shake (and effect) replay.
    @State private var revealCount = 0
    @State private var burning = false
    @State private var showingCertificate = false
    /// Reasoning steps shown so far; they appear one at a time after the reveal.
    @State private var reasoningShown = 0

    var body: some View {
        ZStack {
            if let verdict = session.verdict, let dossier = session.dossier {
                BurnEffect(isBurning: burning, onFinished: { app.scanAgain() }) {
                    ScrollView {
                        VStack(spacing: 22) {
                            header
                            verdictCard(verdict)
                            if !session.reasoning.isEmpty { reasoningSection }
                            dossierSection(dossier, verdict: verdict)
                            if app.aiFieldNotes && session.fieldNotesState != .off { fieldNotesSection }
                            cluesSection(verdict)
                            readingsSection(verdict)
                            actions
                        }
                        .padding(20)
                    }
                    .revealShake(for: verdict.monster, trigger: revealCount)
                }
                .opacity(revealed ? 1 : 0)
                .scaleEffect(revealed || reduceMotion ? 1 : 0.92)

                // Per-monster reveal effect, above the card, below the blackout.
                if revealed && !burning {
                    MonsterRevealEffect(monster: verdict.monster, trigger: session.calibration)
                }
            }
            // Blackout before the reveal.
            Color.black
                .ignoresSafeArea()
                .opacity(revealed ? 0 : 1)
                .allowsHitTesting(!revealed)
        }
        .crtScreen()
        .task(id: session.calibration) { await reveal() }
        .onShake {
            // Shake for a second opinion.
            guard revealed, !burning, !session.isInvisibleVerdict else { return }
            app.secondOpinion()
        }
        .onDisappear { app.narrator.stop() }
        #if DEBUG
        .task {
            // Debug: `-MSShowCertificate` opens the certificate after the reveal (Simulator checks).
            guard ProcessInfo.processInfo.arguments.contains("-MSShowCertificate") else { return }
            try? await Task.sleep(for: .seconds(9))
            showingCertificate = true
        }
        #endif
        .sheet(isPresented: $showingCertificate) {
            if let content = session.certificateContent { CertificateSheet(content: content) }
        }
    }

    private func reveal() async {
        revealed = false
        reasoningShown = 0
        guard let monster = session.verdict?.monster else { return }
        SoundFX.shared.play(.drumroll)
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 1_100))
        if app.hapticsEnabled { app.haptics.revealSpike() }
        SoundFX.shared.play(.sting(monster))
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7)) { revealed = true }
        revealCount += 1
        scheduleImpacts(for: monster)
        Task { await revealReasoning() }
        if app.aiFieldNotes { session.startFieldNotes() }
        // Let the sting land before Agent K-9 starts talking.
        let sting = SoundFX.shared.isEnabled ? SoundFX.shared.duration(of: .sting(monster)) : 0.6
        try? await Task.sleep(for: .seconds(max(0.6, sting)))
        if app.voiceEnabled, let text = session.narrationText { app.narrator.speak(text) }
    }

    /// One step of the Bureau's logic at a time, each with a blip.
    private func revealReasoning() async {
        let steps = session.reasoning.count
        guard !reduceMotion else { reasoningShown = steps; return }
        let calibration = session.calibration
        try? await Task.sleep(for: .seconds(1.2))
        while reasoningShown < steps, revealed, !burning, session.calibration == calibration {
            withAnimation(.easeOut(duration: 0.25)) { reasoningShown += 1 }
            SoundFX.shared.play(.blip)
            try? await Task.sleep(for: .seconds(1.1))
        }
    }

    /// Haptic thumps (and the stamp thud) in time with the reveal effect.
    private func scheduleImpacts(for monster: Monster) {
        for time in MonsterRevealEffect.impactTimes(for: monster) {
            Task {
                try? await Task.sleep(for: .seconds(time))
                guard revealed else { return }
                if app.hapticsEnabled { app.haptics.tap() }
                if monster == .human { SoundFX.shared.play(.stamp) }
            }
        }
    }

    private func burnTheEvidence() {
        app.narrator.stop()
        session.cancelFieldNotes()
        SoundFX.shared.play(.burn)
        if app.hapticsEnabled { app.haptics.startHeartbeat(seconds: 1.5) }
        burning = true
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            if session.isChaos {
                Stamp(text: "CHAOS MODE")
                    .accessibilityLabel("Chaos Mode: the AI is in charge")
            } else {
                Stamp()
            }
            Spacer()
            Button {
                app.voiceEnabled.toggle()
                if app.voiceEnabled, let text = session.narrationText { app.narrator.speak(text) }
            } label: {
                Image(systemName: app.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
            }
            .buttonStyle(IconButtonStyle(active: app.voiceEnabled))
            .accessibilityLabel("Agent voice")
            .accessibilityValue(app.voiceEnabled ? "On" : "Off")
        }
    }

    private func verdictCard(_ verdict: Verdict) -> some View {
        VStack(spacing: 10) {
            Text(verdict.monster == .human ? "SUBJECT IS" : "SUBJECT IS A")
                .font(Theme.mono(.subheadline, weight: .bold))
                .foregroundStyle(Theme.dimNeon)
            Text(verdict.monster.emoji)
                .font(.system(size: 110))
                .accessibilityHidden(true)
            Text(verdict.monster.verdictTitle)
                .font(Theme.mono(.largeTitle, weight: .heavy))
                .foregroundStyle(verdict.monster == .human ? Theme.neon : Theme.alert)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .crtGlow(verdict.monster == .human ? Theme.neon : Theme.alert, radius: 8)
            if let subspecies = session.subspecies {
                Text("SUBSPECIES: \(subspecies.uppercased())")
                    .font(Theme.mono(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.neon)
                    .multilineTextAlignment(.center)
            }
            if session.isChaos {
                Text("THE AI IS IN CHARGE. THE BUREAU TAKES NO RESPONSIBILITY.")
                    .font(Theme.mono(.caption2, weight: .bold))
                    .foregroundStyle(Theme.alert)
                    .multilineTextAlignment(.center)
            }
            Text("CONFIDENCE \(verdict.confidenceText)")
                .font(Theme.mono(.title3, weight: .bold))
                .foregroundStyle(Theme.neon)
                .monospacedDigit()
            Text("CASE \(verdict.caseNumber)" + (session.calibration > 0 ? " · CALIBRATION #\(session.calibration + 1)" : ""))
                .font(Theme.mono(.caption))
                .foregroundStyle(Theme.dimNeon)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .overlay(Rectangle().stroke(Theme.neon.opacity(0.7), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verdict: \(verdict.monster.verdictTitle)\(session.subspecies.map { ", subspecies \($0)" } ?? ""). Confidence \(verdict.confidenceText).")
    }

    /// Numbered steps laid out from the start (unshown ones transparent), so
    /// nothing jumps as they appear.
    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "THE BUREAU'S REASONING")
            ForEach(Array(session.reasoning.enumerated()), id: \.offset) { index, step in
                let isLast = index == session.reasoning.count - 1
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1).")
                        .foregroundStyle(Theme.alert)
                    Text(step)
                        .foregroundStyle(Theme.neon)
                        .fontWeight(isLast ? .bold : .regular)
                    Spacer(minLength: 0)
                }
                .font(Theme.mono(.callout))
                .opacity(index < reasoningShown ? 1 : 0)
                .offset(x: index < reasoningShown || reduceMotion ? 0 : -8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The Bureau's reasoning. " + session.reasoning.joined(separator: " "))
    }

    private func dossierSection(_ dossier: Dossier, verdict: Verdict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "DOSSIER · AGENT K-9")
            TypewriterText(
                text: session.narrationText ?? dossier.fullText,
                spokenCharacters: app.narrator.isSpeaking ? app.narrator.spokenCharacters : nil,
                animated: revealed && !reduceMotion
            )
            .font(Theme.mono(.callout))
            .foregroundStyle(Theme.neon)
        }
    }

    private func cluesSection(_ verdict: Verdict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "EVIDENCE")
            ForEach(Array(verdict.clues.enumerated()), id: \.element.id) { index, clue in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1).")
                        .foregroundStyle(Theme.alert)
                    Text(clue.quip)
                        .foregroundStyle(clue.isAnomaly ? Theme.dimNeon : Theme.neon)
                    Spacer(minLength: 0)
                }
                .font(Theme.mono(.callout))
            }
            ForEach(Array(session.exhibits.enumerated()), id: \.offset) { index, exhibit in
                HStack(alignment: .top, spacing: 10) {
                    Text(["D.", "E.", "F."][min(index, 2)])
                        .foregroundStyle(Theme.alert)
                    Text(exhibit)
                        .foregroundStyle(Theme.neon)
                    Spacer(minLength: 0)
                }
                .font(Theme.mono(.callout))
            }
        }
    }

    private var fieldNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "AGENT K-9'S FIELD NOTES (AI, EXPERIMENTAL)")
            if session.fieldNotes.isEmpty {
                Text(session.fieldNotesState == .writing ? "AGENT K-9 IS SCRIBBLING…" : "NOTHING FIT TO PRINT.")
                    .font(Theme.mono(.caption))
                    .foregroundStyle(Theme.dimNeon)
            } else {
                Text(session.fieldNotes.joined(separator: " "))
                    .font(Theme.mono(.callout))
                    .foregroundStyle(Theme.neon)
                    .animation(.easeOut, value: session.fieldNotes.count)
            }
        }
    }

    private func readingsSection(_ verdict: Verdict) -> some View {
        let o = session.observations
        let rows: [(String, String)] = [
            ("HAIR", label(o.hairColor.rawValue)),
            ("EYES", label(o.eyeColor.rawValue)),
            ("SHIRT", label(o.shirtColor)),
            ("APPARENT EARTH-AGE", "\(label(o.ageBand.rawValue)) · TRUE AGE: \(verdict.trueAgeYears) YEARS"),
            ("EXPRESSION", label(o.expression.rawValue) + (o.expressionRead.map { "\n“\($0)”" } ?? "")),
            ("ACCESSORIES", o.wornAccessories.isEmpty ? "NONE DETECTED"
                : Accessory.allCases.filter(o.wornAccessories.contains).map { $0.rawValue.uppercased() }.joined(separator: ", ")),
            ("SETTING", label(o.backgroundHint)),
            ("SPOTTED", o.funDetails.isEmpty ? "NOTHING UNUSUAL. SUSPICIOUS." : o.funDetails.map { $0.uppercased() }.joined(separator: "\n")),
            ("SCANNER MODE", session.modeLabel),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "SCANNER READINGS")
            ForEach(rows, id: \.0) { name, value in
                HStack(alignment: .firstTextBaseline) {
                    Text(name).foregroundStyle(Theme.dimNeon)
                    Spacer(minLength: 12)
                    Text(value).foregroundStyle(Theme.neon).multilineTextAlignment(.trailing)
                }
                .font(Theme.mono(.caption))
                .accessibilityElement(children: .combine)
            }
            Text("Scanner readings may be wildly inaccurate.")
                .font(Theme.mono(.caption2))
                .foregroundStyle(Theme.dimNeon)
                .padding(.top, 4)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if !session.isInvisibleVerdict {
                Button("Second Opinion (or shake)") { app.secondOpinion() }
                    .buttonStyle(NeonButtonStyle())
                    .accessibilityHint("Re-runs the verdict with a different scanner calibration. You can also shake the phone.")
            }
            if !session.isInvisibleVerdict {
                Button("Certificate of Monsterhood 📜") {
                    app.narrator.stop()
                    showingCertificate = true
                }
                .buttonStyle(NeonButtonStyle())
                .accessibilityHint("Shows a certificate you can share")
            }
            Button("Burn the Evidence 🔥") { burnTheEvidence() }
                .buttonStyle(NeonButtonStyle(color: Theme.alert))
                .disabled(burning)
                .accessibilityHint("Burns the photo and result away, then returns to the camera")
            Button("Scan Again") { app.scanAgain() }
                .buttonStyle(NeonButtonStyle(filled: true))
                .accessibilityHint("Forgets this photo and result")
        }
        .padding(.top, 8)
    }

    private func label(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.lowercased() == "unknown" ? "CLASSIFIED" : trimmed.uppercased()
    }
}

/// Types text out, keeping pace with the narrator when it is speaking.
/// The full text is laid out from the start (unrevealed part transparent),
/// so the layout doesn't jump.
struct TypewriterText: View {
    let text: String
    /// Characters spoken so far, or nil when not narrating.
    let spokenCharacters: Int?
    let animated: Bool

    @State private var typed = 0
    @State private var startedAt = Date.now

    /// How far typing may run ahead of the voice.
    private let leadOverVoice = 45
    /// If the voice hasn't started by then, stop waiting for it.
    private let voiceGrace: TimeInterval = 3

    private var visible: Int {
        guard animated else { return text.count }
        if let spokenCharacters, spokenCharacters > 0 || Date.now.timeIntervalSince(startedAt) < voiceGrace {
            return min(typed, spokenCharacters + leadOverVoice)
        }
        return typed
    }

    var body: some View {
        Text(attributed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
            .task(id: "\(text)|\(animated)") {
                guard animated else { typed = text.count; return }
                typed = 0
                startedAt = .now
                while typed < text.count && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(30))
                    typed += 1
                }
            }
    }

    private var attributed: AttributedString {
        let count = min(visible, text.count)
        var shown = AttributedString(String(text.prefix(count)))
        var hidden = AttributedString(String(text.dropFirst(count)))
        hidden.foregroundColor = .clear
        shown.append(hidden)
        return shown
    }
}

/// "No subject detected. Are they… invisible? 👻"
struct NoSubjectView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("👻").font(.system(size: 96)).accessibilityHidden(true)
            Text("NO SUBJECT DETECTED")
                .font(Theme.mono(.title2, weight: .heavy))
                .foregroundStyle(Theme.alert)
                .crtGlow(Theme.alert, radius: 6)
            Text("Are they… invisible?")
                .font(Theme.mono(.title3))
                .foregroundStyle(Theme.neon)
            Text("The scanner couldn't find a face. Make sure the subject is facing the camera, in decent light.")
                .font(Theme.mono(.footnote))
                .foregroundStyle(Theme.dimNeon)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 12) {
                Button("Declare them a Ghost") { app.declareGhost() }
                    .buttonStyle(NeonButtonStyle(color: Theme.alert))
                Button("Try again") { app.scanAgain() }
                    .buttonStyle(NeonButtonStyle(filled: true))
            }
        }
        .padding(24)
        .crtScreen()
    }
}
