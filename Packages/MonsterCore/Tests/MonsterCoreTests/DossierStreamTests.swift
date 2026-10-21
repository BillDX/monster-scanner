import Testing
@testable import MonsterCore

@Suite("AI dossier: prompt and streaming filter")
struct DossierStreamTests {
    static func input(_ monster: Monster = .vampire) -> DossierInput {
        var input = DossierInput(
            monster: monster, clueEvidence: ["a black shirt", "a photo taken at 23:41", "sunglasses indoors"],
            shirtColor: "black", confidenceText: "87.3%", caseNumber: "K9-1234", trueAgeYears: 412, seed: 99
        )
        input.subspecies = "Brunch Bat"
        input.funDetails = ["a top hat", "two red balloons"]
        input.expressionRead = "like a happy little sunbeam"
        input.vibe = "a whimsical adventurer on a magical journey"
        input.setting = "living room"
        return input
    }

    /// Feeds text in small chunks, like a token stream.
    static func stream(_ text: String, verdict: Monster = .vampire, chunk: Int = 3) -> DossierStreamFilter {
        var filter = DossierStreamFilter(verdict: verdict)
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: chunk, limitedBy: text.endIndex) ?? text.endIndex
            _ = filter.feed(String(text[index..<end]))
            index = end
        }
        _ = filter.finish()
        return filter
    }

    @Test("Prompt carries the verdict, evidence and kindness rules, but no hair, eyes or age")
    func prompt() {
        let text = DossierPrompt.user(for: Self.input())
        #expect(text.contains("subject is a VAMPIRE"))
        #expect(text.contains("a black shirt; a photo taken at 23:41; sunglasses indoors"))
        #expect(text.contains("spotted: a top hat; two red balloons"))
        #expect(text.contains("subspecies: Brunch Bat"))
        #expect(text.contains("Never mention skin or skin colour, race, ethnicity"))
        #expect(text.contains("Do not suggest any other monster"))
        #expect(!text.lowercased().contains("hair:") && !text.lowercased().contains("eyes:") && !text.contains("age band"))
        #expect(DossierPrompt.user(for: Self.input(.human)).contains("CERTIFIED HUMAN"))
    }

    @Test("A good stream becomes a dossier")
    func goodStream() throws {
        let text = "CLASSIFIED. The subject is a vampire of the brunch variety. Exhibit A: a black shirt worn at 23:41! "
            + "Their top hat suggests centuries of dramatic entrances.\n\nRecommended action: Offer garlic bread, then run."
        let filter = Self.stream(text)
        let dossier = try #require(filter.dossier())
        #expect(filter.acceptedSentences.count == 4)
        #expect(dossier.recommendedAction == "Offer garlic bread, then run.")
        #expect(dossier.body.hasPrefix("CLASSIFIED."))
    }

    @Test("Unkind or sensitive sentences are dropped silently")
    func dropsUnkind() {
        let text = "The subject is a vampire. They look a bit sad and awkward today. Their skin is very pale. "
            + "But that cape-friendly black shirt is magnificent!\n\nRecommended action: Applaud the cape."
        let filter = Self.stream(text)
        #expect(filter.acceptedSentences == ["The subject is a vampire.", "But that cape-friendly black shirt is magnificent!"])
        #expect(filter.rejectedSentences.count == 2)
        #expect(filter.isUsable)
    }

    @Test("Sentences naming a different monster are dropped (the code decides)")
    func dropsOtherMonsters() {
        let text = "The subject is a vampire. Or possibly a robot, who knows. Zombies everywhere are jealous. "
            + "The undead would approve. Their cape game is strong.\n\nRecommended action: Dim the lights."
        let filter = Self.stream(text)
        #expect(filter.acceptedSentences == ["The subject is a vampire.", "Their cape game is strong."])
    }

    @Test("Too little left, or no recommended action, means the template is used")
    func fallsBack() {
        #expect(!Self.stream("The subject is a vampire. Their skin is pale.\n\nRecommended action: Run.").isUsable)
        #expect(!Self.stream("The subject is a vampire. A fine cape. A dramatic hat.").isUsable)
    }

    @Test("Sentence splitting leaves numbers and names intact")
    func splitting() {
        let (sentences, rest) = DossierStreamFilter.split("Confidence 87.3% is high. Agent K-9 agrees! Next")
        #expect(sentences == ["Confidence 87.3% is high.", " Agent K-9 agrees!"])
        #expect(rest == " Next")
    }

    @Test("The word limit is enforced")
    func wordLimit() {
        let long = String(repeating: "The subject is a vampire with a very fine cape indeed. ", count: 20)
        let filter = Self.stream(long + "\n\nRecommended action: Bow.")
        #expect(filter.body.split(separator: " ").count <= DossierStreamFilter.maxWords)
    }

    @Test("Subspecies and jokes are kind, and every verdict has 8 subspecies")
    func extrasAreKind() {
        for monster in Monster.allCases {
            let list = Subspecies.catalogue[monster] ?? []
            #expect(list.count == 8, "\(monster)")
            for name in list { #expect(ContentPolicy.isAllowed(name), "\(name)") }
        }
        for line in Jokes.bootChecks + Jokes.scanFlavour {
            #expect(ContentPolicy.isAllowed(line), "\(line)")
        }
        #expect(Set((0..<20).map { Subspecies.name(for: .robot, seed: UInt64($0) << 29) }).count > 4)
        #expect(Jokes.flavour(count: 3, seed: 1) == Jokes.flavour(count: 3, seed: 1))
    }
}

@Suite("Chaos Mode")
struct ChaosModeTests {
    @Test("The chaos grammar adds monster_scores for every monster")
    func grammar() {
        #expect(ChaosMode.grammar.contains("monster_scores"))
        for monster in Monster.scorable { #expect(ChaosMode.grammar.contains("\\\"\(monster.rawValue)\\\"")) }
        #expect(ChaosMode.grammar.contains("score ::="))
        #expect(ChaosMode.user.contains("monster_scores"))
    }

    @Test("Scores are parsed and clamped")
    func scores() throws {
        let raw = #"{"hair_color":"brown","monster_scores":{"vampire":140,"alien":-5,"kaiju":33,"robot":"x"}}"#
        let scores = try #require(ChaosMode.scores(from: raw))
        #expect(scores[.vampire] == 100 && scores[.alien] == 0 && scores[.kaiju] == 33)
        #expect(scores[.robot] == 0 && scores[.ghost] == 0)
        #expect(ChaosMode.scores(from: "no json") == nil)
    }

    @Test("The AI's top score wins; weak scores make a human")
    func verdicts() {
        let evidence = Fixtures.strong[.robot]!
        let alien = VerdictEngine.chaos(evidence, scores: [.alien: 88, .robot: 20], seed: 5)
        #expect(alien.monster == .alien)
        #expect(alien.clues.count == 3 && alien.clues.allSatisfy { $0.monster == .alien })
        #expect((51...99.9).contains(alien.confidence))
        #expect(alien.caseNumber.hasPrefix("C4-"))

        let human = VerdictEngine.chaos(evidence, scores: [.alien: 12, .robot: 30], seed: 5)
        #expect(human.monster == .human && human.clues.count == 3)

        // The code's evidence stays code-written and kind.
        for clue in alien.clues + human.clues { #expect(ContentPolicy.isAllowed(clue.quip)) }
    }
}

@Suite("Exhibit jokes")
struct ExhibitTests {
    static let props = SubjectObservations(
        shirtColor: "navy blue", expression: .smiling, accessories: [.hat, .sunglasses, .mask],
        funDetails: ["a top hat", "two red balloons", "a cup of coffee"]
    )

    @Test("Things come from spotted details, then accessories, then the shirt; never the mask")
    func things() {
        let things = Exhibits.things(in: Self.props)
        #expect(things == ["top hat", "two red balloons", "cup of coffee", "sunglasses", "navy blue shirt"])
        #expect(!things.contains("mask"))
        #expect(Exhibits.things(in: .unknown).isEmpty)
    }

    @Test("Every verdict has 8 kind exhibit jokes that fill cleanly", arguments: Monster.allCases)
    func jokes(_ monster: Monster) {
        let templates = Exhibits.jokes[monster] ?? []
        #expect(templates.count == 8)
        for template in templates {
            for thing in ["top hat", "two red balloons", "navy blue shirt", "sunglasses"] {
                let line = Exhibits.fill(template, thing: thing)
                #expect(!line.contains("{") && ContentPolicy.isAllowed(line), "\(line)")
                #expect(line.first?.isUppercase == true, "\(line)")
            }
        }
    }

    @Test("Lines are seeded, distinct and about different things")
    func lines() {
        let a = Exhibits.lines(for: .robot, observations: Self.props, seed: 7)
        #expect(a.count == 2)
        #expect(a == Exhibits.lines(for: .robot, observations: Self.props, seed: 7))
        #expect(a[0].contains("top hat") || a[0].contains("Top hat"))
        #expect(a[1].localizedCaseInsensitiveContains("balloons"))
        let variety = Set((0..<20).map { Exhibits.lines(for: .robot, observations: Self.props, seed: UInt64($0)).first ?? "" })
        #expect(variety.count > 4)
    }
}
