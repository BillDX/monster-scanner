import Foundation
import Testing
@testable import MonsterCore

@Suite("Content: templates, clues and the kindness check")
struct ContentTests {
    static let library = DossierLibrary.bundled
    static let allowedSlots: Set<String> = [
        "{verdict}", "{clue_1}", "{clue_2}", "{clue_3}", "{shirt_color}", "{confidence}", "{case_number}", "{true_age}",
    ]

    // MARK: Templates

    @Test("At least 8 templates per verdict", arguments: Monster.allCases)
    func templateCount(_ monster: Monster) {
        #expect((Self.library.templates[monster] ?? []).count >= 8)
    }

    @Test("Templates only use known slots")
    func slots() throws {
        let regex = try NSRegularExpression(pattern: "\\{[a-z_0-9]+\\}")
        for (monster, templates) in Self.library.templates {
            for template in templates {
                let text = template.text + " " + template.action
                let found = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    .map { String(text[Range($0.range, in: text)!]) }
                for slot in found {
                    #expect(Self.allowedSlots.contains(slot), "\(monster): unknown slot \(slot)")
                }
                // S-2: no hair, eye or age slots in dossiers.
                #expect(!text.contains("{hair_color}") && !text.contains("{eye_color}") && !text.contains("{age_band}"))
            }
        }
    }

    @Test("Every template renders cleanly, under 110 words, and passes the kindness check")
    func renderedTemplates() {
        // Render each template with clues from many different photos.
        for (index, evidence) in Fixtures.random(count: 400).enumerated() {
            let verdict = VerdictEngine.decide(evidence, seed: Fixtures.seed(index))
            let input = DossierInput(verdict: verdict, observations: evidence.observations)
            for template in Self.library.templates[verdict.monster] ?? [] {
                let dossier = DossierLibrary.render(template, with: input)
                let text = dossier.fullText
                #expect(!text.contains("{") && !text.contains("}"), "unfilled slot: \(text)")
                #expect(dossier.wordCount <= 110, "\(dossier.wordCount) words: \(text)")
                #expect(ContentPolicy.isAllowed(text), "\(ContentPolicy.violations(in: text)): \(text)")
            }
        }
    }

    @Test("Template choice follows the seed")
    func templateChoice() {
        let evidence = Fixtures.strong[.robot]!
        let verdict = VerdictEngine.decide(evidence, seed: Fixtures.seed(0))
        let input = DossierInput(verdict: verdict, observations: evidence.observations)
        #expect(Self.library.write(input) == Self.library.write(input))
        let picked = Set((0..<40).map { calibration -> String in
            let v = VerdictEngine.decide(evidence, seed: Fixtures.seed(calibration))
            return Self.library.write(DossierInput(verdict: v, observations: evidence.observations)).body
        })
        #expect(picked.count >= 4)
    }

    // MARK: Clues, telemetry and fixed strings

    @Test("Every clue, anomaly line and telemetry line passes the kindness check")
    func cluesAndTelemetry() {
        var texts: [String] = []
        for evidence in Fixtures.random(count: 1_500) + Array(Fixtures.strong.values) {
            for rule in ClueBook.rules {
                if let clue = rule.clue(for: evidence) { texts += [clue.evidence, clue.quip] }
            }
            texts += Telemetry.lines(for: evidence, moonName: "FULL MOON")
        }
        for list in ClueBook.anomalies.values { texts += list.flatMap { [$0.evidence, $0.quip] } }
        texts += ClueBook.humanReasons.flatMap { [$0.evidence, $0.quip] }
        texts += Telemetry.warmUp
        texts += Monster.allCases.map(\.verdictTitle)
        texts += [VerdictEngine.invisibleSubject(seed: 1)].flatMap { $0.clues.flatMap { [$0.evidence, $0.quip] } }

        for text in Set(texts) {
            #expect(ContentPolicy.isAllowed(text), "\(ContentPolicy.violations(in: text)): \(text)")
        }
    }

    @Test("Telemetry shows real measured values")
    func telemetryValues() {
        let evidence = Fixtures.evidence { m, o in
            m.moonIllumination = 0.94; m.shirtHueDegrees = 212; o.shirtColor = "blue"
            m.minutesSinceMidnight = 23 * 60 + 41; m.batteryLevel = 0.18
        }
        let lines = Telemetry.lines(for: evidence)
        #expect(lines.contains("SHIRT HUE: 212° (SUSPICIOUSLY BLUE)"))
        #expect(lines.contains("MOON PHASE: 94% (DANGER)"))
        #expect(lines.contains("LOCAL TIME: 23:41 (NOCTURNAL)"))
        #expect(lines.contains("BATTERY: 18% (DRAINED BY VAMPIRES?)"))
    }

    // MARK: The checker itself

    @Test("The checker catches banned topics", arguments: [
        "Their pale skin gives it away.",
        "Looking a bit wrinkly today.",
        "That's an ugly shirt.",
        "Judging by their weight…",
        "Must be their ethnicity.",
        "They seem sick.",
        "A trail of blood.",
        "What an idiot.",
        "Clearly over the hill.",
        "Big BODY energy.",
    ])
    func catchesBanned(_ text: String) {
        #expect(!ContentPolicy.isAllowed(text))
    }

    @Test("The checker leaves ordinary words alone", arguments: [
        "The subject is undead but delightful.",
        "A tangerine shirt, a scary story and a willing friend.",
        "Dielectric antenna array calibrated.",
        "Skinnerian conditioning not detected.",
        "The subject's shadow is present.",
        "BLUR INDEX: 400 (STABLE)",
    ])
    func allowsOrdinary(_ text: String) {
        #expect(ContentPolicy.isAllowed(text), "\(ContentPolicy.violations(in: text))")
    }
}
