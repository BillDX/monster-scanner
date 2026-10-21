import Testing
@testable import MonsterCore

@Suite("Observation JSON parser")
struct ObservationParserTests {
    static let clean = """
    {"hair_color":"brown","eye_color":"blue","shirt_color":"navy blue","age_band":"30s","expression":"smiling","accessories":["glasses"],"background_hint":"city park"}
    """

    @Test("Clean JSON parses exactly")
    func parsesCleanJSON() throws {
        let o = try ObservationParser.parse(Self.clean).get()
        #expect(o.hairColor == .brown)
        #expect(o.eyeColor == .blue)
        #expect(o.shirtColor == "navy blue")
        #expect(o.shirtFamily == .blue)
        #expect(o.ageBand == .thirties)
        #expect(o.expression == .smiling)
        #expect(o.accessories == [.glasses])
        #expect(o.backgroundHint == "city park")
        #expect(o.setting == .outdoors)
    }

    // MARK: 20 malformed outputs (spec section 8)

    /// Outputs that should be repaired into usable observations.
    static let repairable: [(String, String)] = [
        ("code fence", "```json\n" + clean + "\n```"),
        ("prose before and after", "Sure! Here is the JSON you asked for:\n" + clean + "\nHope that helps."),
        ("trailing commas", #"{"hair_color":"black","eye_color":"brown","shirt_color":"red","age_band":"20s","expression":"serious","accessories":["hat",],"background_hint":"kitchen",}"#),
        ("curly quotes", "{\u{201C}hair_color\u{201D}:\u{201C}black\u{201D},\u{201C}eye_color\u{201D}:\u{201C}brown\u{201D},\u{201C}shirt_color\u{201D}:\u{201C}red\u{201D},\u{201C}age_band\u{201D}:\u{201C}20s\u{201D},\u{201C}expression\u{201D}:\u{201C}serious\u{201D},\u{201C}accessories\u{201D}:[],\u{201C}background_hint\u{201D}:\u{201C}office\u{201D}}"),
        ("synonyms everywhere", #"{"hair_color":"Grey","eye_color":"grey","shirt_color":"Charcoal","age_band":"thirties","expression":"neutral","accessories":["eyeglasses","earbuds"],"background_hint":"Living Room"}"#),
        ("odd key styles", #"{"Hair Color":"blond","eyeColor":"green","shirt-color":"white","AGE_BAND":"teenager","Expression":"happy","accessories":"hat, scarf","backgroundHint":"beach"}"#),
        ("one key missing", #"{"hair_color":"red","eye_color":"hazel","shirt_color":"green","age_band":"40s","expression":"sleepy","accessories":[]}"#),
        ("unknown enum values", #"{"hair_color":"rainbow sparkle","eye_color":"violet","shirt_color":"teal","age_band":"ancient","expression":"mysterious","accessories":["monocle","cape"],"background_hint":"castle"}"#),
        ("numeric age", #"{"hair_color":"brown","eye_color":"brown","shirt_color":"black","age_band":"35","expression":"surprised","accessories":["none"],"background_hint":"street"}"#),
        ("age range", #"{"hair_color":"brown","eye_color":"brown","shirt_color":"black","age_band":"50-59","expression":"silly","accessories":[],"background_hint":"bar"}"#),
        ("too many accessories", #"{"hair_color":"black","eye_color":"brown","shirt_color":"blue","age_band":"20s","expression":"smiling","accessories":["glasses","hat","scarf","necklace","earrings","hat"],"background_hint":"party"}"#),
        ("long free text", #"{"hair_color":"black","eye_color":"brown","shirt_color":"a lovely deep forest green knitted jumper","age_band":"20s","expression":"smiling","accessories":[],"background_hint":"a very busy and noisy downtown restaurant at night"}"#),
        ("banned words in free text", #"{"hair_color":"black","eye_color":"brown","shirt_color":"blue","age_band":"20s","expression":"smiling","accessories":[],"background_hint":"hospital wheelchair ramp"}"#),
        ("nested in an array", "[" + clean + "]"),
    ]

    @Test("Repairable outputs give usable observations", arguments: repairable)
    func repairs(_ name: String, _ raw: String) {
        #expect((try? ObservationParser.parse(raw).get()) != nil, "\(name) should parse")
    }

    @Test("Specific repairs map values sensibly")
    func mappings() throws {
        let synonyms = try ObservationParser.parse(Self.repairable[4].1).get()
        #expect(synonyms.hairColor == .gray && synonyms.eyeColor == .gray && synonyms.shirtFamily == .gray)
        #expect(synonyms.ageBand == .thirties && synonyms.expression == .serious)
        #expect(synonyms.accessories == [.glasses, .headphones])

        let keys = try ObservationParser.parse(Self.repairable[5].1).get()
        #expect(keys.hairColor == .blonde && keys.ageBand == .teen && keys.expression == .smiling)
        #expect(keys.accessories == [.hat, .scarf])

        let missing = try ObservationParser.parse(Self.repairable[6].1).get()
        #expect(missing.backgroundHint == "unknown")

        let unknowns = try ObservationParser.parse(Self.repairable[7].1).get()
        #expect(unknowns.hairColor == .unknown && unknowns.eyeColor == .unknown)
        #expect(unknowns.ageBand == .unknown && unknowns.expression == .unknown && unknowns.accessories.isEmpty)

        #expect(try ObservationParser.parse(Self.repairable[8].1).get().ageBand == .thirties)
        #expect(try ObservationParser.parse(Self.repairable[9].1).get().ageBand == .fifties)
        #expect(try ObservationParser.parse(Self.repairable[9].1).get().expression == .sillyFace)
        #expect(try ObservationParser.parse(Self.repairable[10].1).get().accessories == [.glasses, .hat, .scarf])

        let long = try ObservationParser.parse(Self.repairable[11].1).get()
        #expect(long.shirtColor.split(separator: " ").count <= 3)
        #expect(long.backgroundHint.split(separator: " ").count <= 4)

        #expect(try ObservationParser.parse(Self.repairable[12].1).get().backgroundHint == "unknown")
    }

    /// Outputs that must fail cleanly, so the caller retries / falls back.
    static let failures: [(String, String, ObservationParser.Failure)] = [
        ("empty", "", .empty),
        ("whitespace", "   \n ", .empty),
        ("prose only", "The person has brown hair and is smiling.", .noJSONObject),
        ("truncated", #"{"hair_color":"brown","eye_color":"bl"#, .noJSONObject),
        ("single quotes", "{'hair_color':'brown','eye_color':'blue'}", .invalidJSON),
        ("wrong schema", #"{"name":"Bob","mood":"great"}"#, .tooFewKeys(found: 0)),
    ]

    @Test("Unusable outputs fail cleanly", arguments: failures)
    func failsCleanly(_ name: String, _ raw: String, _ expected: ObservationParser.Failure) {
        switch ObservationParser.parse(raw) {
        case .success: Issue.record("\(name) should have failed")
        case .failure(let failure): #expect(failure == expected, "\(name)")
        }
    }

    @Test("There are 20 malformed cases")
    func malformedCaseCount() {
        #expect(Self.repairable.count + Self.failures.count == 20)
    }

    // MARK: Playful fields (D-021)

    static let playfulJSON = """
    {"hair_color":"brown","eye_color":"brown","shirt_color":"red","age_band":"20s","expression":"smiling",
     "expression_read":"grinning like they just found free cake","accessories":["hat","glasses"],
     "fun_details":["red bobble hat","round glasses","thumbs up","fairy lights behind"],
     "vibe":"radiates the calm of a wizard on holiday","background_hint":"living room"}
    """

    @Test("Playful fields parse and are capped")
    func playfulFields() throws {
        let o = try ObservationParser.parse(Self.playfulJSON).get()
        #expect(o.expressionRead == "grinning like they just found free cake")
        #expect(o.vibe == "radiates the calm of a wizard on holiday")
        #expect(o.funDetails == ["red bobble hat", "round glasses", "thumbs up"])
        #expect(o.accessories == [.hat, .glasses])
    }

    @Test("Sunglasses win over glasses; settings don't end on filler words")
    func cleanUps() throws {
        let raw = """
        {"hair_color":"brown","eye_color":"brown","shirt_color":"blue","age_band":"30s","expression":"smiling",
         "accessories":["sunglasses","hat","glasses"],"background_hint":"a pink square with lots of balloons"}
        """
        let o = try ObservationParser.parse(raw).get()
        #expect(o.accessories == [.sunglasses, .hat])
        #expect(o.backgroundHint == "a pink square")
    }

    @Test("Unkind or sensitive playful text is dropped, the rest kept")
    func playfulGuardrails() throws {
        let raw = """
        {"hair_color":"brown","eye_color":"brown","shirt_color":"blue","age_band":"30s","expression":"serious",
         "expression_read":"looking a bit sad and awkward","accessories":[],
         "fun_details":["dark-skinned man","cool denim jacket","beard of a wizard"],
         "vibe":"wise like an old owl","background_hint":"kitchen"}
        """
        let o = try ObservationParser.parse(raw).get()
        #expect(o.expressionRead == nil)
        #expect(o.vibe == nil)
        #expect(o.funDetails == ["cool denim jacket"])
        #expect(o.shirtFamily == .blue && o.expression == .serious) // core reading survives
    }

    @Test("Missing, 'unknown' or over-long playful text is handled")
    func playfulEdgeCases() throws {
        // The spec-only shape (no playful keys) still parses.
        let plain = try ObservationParser.parse(Self.clean).get()
        #expect(plain.expressionRead == nil && plain.vibe == nil && plain.funDetails.isEmpty)

        let raw = """
        {"hair_color":"brown","eye_color":"brown","shirt_color":"blue","age_band":"30s","expression":"smiling",
         "expression_read":"unknown","accessories":[],"fun_details":"none",
         "vibe":"one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen",
         "background_hint":"kitchen"}
        """
        let o = try ObservationParser.parse(raw).get()
        #expect(o.expressionRead == nil)
        #expect(o.funDetails.isEmpty)
        #expect(o.vibe == nil) // 16 words: dropped, not chopped mid-sentence
    }

    // MARK: Grammar

    @Test("The grammar names every allowed value and all seven keys")
    func grammarCoversSchema() {
        let g = ObservationPrompt.grammar
        for key in ["hair_color", "eye_color", "shirt_color", "age_band", "expression", "expression_read",
                    "accessories", "fun_details", "vibe", "background_hint"] {
            #expect(g.contains("\\\"\(key)\\\""), "missing \(key)")
        }
        for value in HairColor.allCases.map(\.rawValue) + AgeBand.allCases.map(\.rawValue) + Accessory.allCases.map(\.rawValue) {
            #expect(g.contains("\\\"\(value)\\\""), "missing \(value)")
        }
        #expect(g.hasPrefix("root ::="))
    }

    @Test("The prompt keeps the spec's kindness rules")
    func promptKeepsKindnessRules() {
        #expect(ObservationPrompt.user.contains("Do not describe skin, body shape, weight, ethnicity"))
        #expect(ObservationPrompt.user.contains("Never mention skin or skin colour, race, ethnicity"))
        #expect(ObservationPrompt.retryUser.hasSuffix("Return only valid JSON."))
    }
}
