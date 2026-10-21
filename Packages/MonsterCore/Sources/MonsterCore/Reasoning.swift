import Foundation

/// "THE BUREAU'S REASONING": an after-the-fact chain of absurd logic that
/// leads, with total confidence, to whatever the verdict already was
/// (DECISIONS.md D-027). Code-written from pools, seeded, kind.
///
///   1. Subject is wearing a navy blue shirt.
///   2. Studies link the navy blue shirt to people who sleep upside down, with 312% certainty.
///   3. People who sleep upside down are 98.1% more likely to be vampires. That's just maths.
///   4. Then the scanner hiccupped, which only ever happens near vampires.
///   5. Therefore: VAMPIRE. The logic is airtight. Please do not check it.
public enum Reasoning {
    /// A habit in three grammatical forms: base, past participle, -ing.
    struct Habit: Sendable {
        let base: String
        let past: String
        let ing: String
    }

    static let habits: [Monster: [Habit]] = [
        .vampire: [
            Habit(base: "sleep upside down", past: "slept upside down", ing: "sleeping upside down"),
            Habit(base: "avoid mirrors", past: "avoided a mirror", ing: "avoiding mirrors"),
            Habit(base: "wear capes to brunch", past: "worn a cape to brunch", ing: "wearing capes to brunch"),
            Habit(base: "order tomato juice at parties", past: "ordered tomato juice at a party", ing: "ordering tomato juice at parties"),
            Habit(base: "make dramatic entrances", past: "made a dramatic entrance", ing: "making dramatic entrances"),
        ],
        .alien: [
            Habit(base: "phone home on Sundays", past: "phoned home", ing: "phoning home"),
            Habit(base: "wave at satellites", past: "waved at a satellite", ing: "waving at satellites"),
            Habit(base: "take notes on Earth snacks", past: "taken notes on a crisp", ing: "taking notes on Earth snacks"),
            Habit(base: "collect crop circles", past: "collected a crop circle", ing: "collecting crop circles"),
            Habit(base: "ask to see the leader", past: "asked to see the leader", ing: "asking to see the leader"),
        ],
        .kaiju: [
            Habit(base: "nap in harbours", past: "napped in a harbour", ing: "napping in harbours"),
            Habit(base: "stomp on model railways", past: "stomped on a model railway", ing: "stomping on model railways"),
            Habit(base: "roar at the sea", past: "roared at the sea", ing: "roaring at the sea"),
            Habit(base: "finish an entire buffet", past: "finished an entire buffet", ing: "finishing entire buffets"),
            Habit(base: "tiptoe around skyscrapers", past: "tiptoed around a skyscraper", ing: "tiptoeing around skyscrapers"),
        ],
        .werewolf: [
            Habit(base: "chase frisbees at midnight", past: "chased a frisbee at midnight", ing: "chasing frisbees at midnight"),
            Habit(base: "howl along to the radio", past: "howled along to the radio", ing: "howling along to the radio"),
            Habit(base: "fetch tennis balls", past: "fetched a tennis ball", ing: "fetching tennis balls"),
            Habit(base: "do zoomies after dinner", past: "done zoomies after dinner", ing: "doing zoomies after dinner"),
            Habit(base: "check the moon before going out", past: "checked the moon", ing: "checking the moon"),
        ],
        .zombie: [
            Habit(base: "hit snooze seven times", past: "hit snooze seven times", ing: "hitting snooze seven times"),
            Habit(base: "shuffle to the coffee machine", past: "shuffled to the coffee machine", ing: "shuffling to the coffee machine"),
            Habit(base: "eat brunch instead of brains", past: "eaten brunch instead of brains", ing: "eating brunch instead of brains"),
            Habit(base: "groan at alarm clocks", past: "groaned at an alarm clock", ing: "groaning at alarm clocks"),
            Habit(base: "wear slippers outside", past: "worn slippers outside", ing: "wearing slippers outside"),
        ],
        .robot: [
            Habit(base: "alphabetise their spice rack", past: "alphabetised a spice rack", ing: "alphabetising spice racks"),
            Habit(base: "update their firmware on Tuesdays", past: "updated their firmware", ing: "updating firmware on Tuesdays"),
            Habit(base: "beep when nobody is looking", past: "beeped when nobody was looking", ing: "beeping when nobody is looking"),
            Habit(base: "beat toasters at chess", past: "beaten a toaster at chess", ing: "beating toasters at chess"),
            Habit(base: "fold laundry in perfect squares", past: "folded laundry in perfect squares", ing: "folding laundry in perfect squares"),
        ],
        .ghost: [
            Habit(base: "walk through walls", past: "walked through a wall", ing: "walking through walls"),
            Habit(base: "rattle teacups at midnight", past: "rattled a teacup at midnight", ing: "rattling teacups at midnight"),
            Habit(base: "appear in the background of group photos", past: "appeared in a group photo uninvited", ing: "appearing in the background of group photos"),
            Habit(base: "say boo to pigeons", past: "said boo to a pigeon", ing: "saying boo to pigeons"),
            Habit(base: "creak doors for fun", past: "creaked a door for fun", ing: "creaking doors for fun"),
        ],
        .human: [
            Habit(base: "pay bills on time", past: "paid a bill on time", ing: "paying bills on time"),
            Habit(base: "eat salad on purpose", past: "eaten a salad on purpose", ing: "eating salad on purpose"),
            Habit(base: "read the terms and conditions", past: "read the terms and conditions", ing: "reading the terms and conditions"),
            Habit(base: "water their houseplants", past: "watered a houseplant", ing: "watering houseplants"),
            Habit(base: "say 'you too' when a waiter says enjoy your meal", past: "said 'you too' to a waiter", ing: "saying 'you too' to waiters"),
        ],
    ]

    static let plurals: [Monster: String] = [
        .vampire: "vampires", .alien: "aliens", .kaiju: "kaiju", .werewolf: "werewolves",
        .zombie: "zombies", .robot: "robots", .ghost: "ghosts", .human: "humans",
    ]

    /// Step 1: what the scanner "saw".
    struct Fact {
        let statement: String  // "Subject is wearing a navy blue shirt."
        let phrase: String     // "the navy blue shirt"
    }

    static func facts(_ e: ScanEvidence) -> [Fact] {
        let m = e.measurements
        var facts: [Fact] = Exhibits.things(in: e.observations).prefix(2).map { thing in
            thing.hasSuffix("shirt")
                ? Fact(statement: "Subject is wearing a \(thing).", phrase: "the \(thing)")
                : Fact(statement: "Exhibit A: the \(thing).", phrase: "the \(thing)")
        }
        facts.append(Fact(statement: "Subject was photographed at \(m.clockText).", phrase: "being photographed at \(m.clockText)"))
        facts.append(Fact(statement: "The moon was \(Fmt.pct(m.moonIllumination)) full at the time.",
                          phrase: "the moon being \(Fmt.pct(m.moonIllumination)) full"))
        if let battery = m.batteryLevel {
            facts.append(Fact(statement: "The scanner's battery read \(Fmt.pct(battery)).", phrase: "a battery reading of \(Fmt.pct(battery))"))
        }
        if let tilt = m.headTilt {
            facts.append(Fact(statement: "Subject's head was tilted \(Fmt.deg(tilt)).", phrase: Fmt.a("\(Fmt.deg(tilt)) head tilt")))
        }
        return facts
    }

    // {x} = the fact phrase, {habit}/{past}/{ing} = a habit, {stat} = a silly number,
    // {monster} / {monsters} / {MONSTER} = the verdict.
    static let leaps = [
        "Studies link {x} to people who {habit}, with {stat} certainty.",
        "The Bureau's 1987 handbook lists {x} under 'people who {habit}'. Page 12, in bold.",
        "Our lab ran {x} through the analyser. It came back {stat} positive for '{ing}'.",
        "Nothing says '{ing}' quite like {x}. Ask anyone.",
        "Historically, {x} has only been spotted near people who have {past}.",
        "According to a pigeon we consulted, {x} is a sure sign of {ing}.",
    ]

    static let bridges = [
        "People who {habit} are {stat2} more likely to be {monsters}. That's just maths.",
        "And {ing} is a classic {monster} hobby. Everyone knows this.",
        "The last person caught {ing} turned out to be a {monster}. Twice.",
        "Every {monster} the Bureau has ever met enjoys {ing}.",
        "Nobody has ever {past} without being at least a little bit {monster}.",
    ]

    static let humanBridges = [
        "And {ing} is the most human thing imaginable. Sigh.",
        "No monster in recorded history has ever bothered {ing}.",
        "Monsters simply do not have time for {ing}. Humans, alas, do.",
    ]

    static let wildcardTwists = [
        "Then the scanner hiccupped, which only ever happens near {monsters}.",
        "At that exact moment a lamp flickered. Classic {monster} behaviour.",
        "Also, the radar hamster refused to make eye contact. It only does that around {monsters}.",
        "Out of nowhere, the readings spiked. The Bureau calls this 'a hunch'.",
        "The scanner then sneezed. It is allergic to {monsters}.",
    ]

    static let corroborations = [
        "This is backed up by {clue}, which nobody can explain.",
        "Exhibit B, {clue}, seals the deal.",
        "Cross-check: {clue}. Suspiciously consistent.",
        "Then there's {clue}. Case practically closes itself.",
    ]

    static let humanCorroborations = [
        "The scanner did pick up {clue}, but only a little. Not enough. Never enough.",
        "Yes, there was {clue}. The Bureau checked it twice. Still nothing.",
        "A brief flicker of hope: {clue}. It faded.",
    ]

    static let conclusions = [
        "Therefore: {MONSTER}. The logic is airtight. Please do not check it.",
        "Conclusion: {MONSTER}. Q.E.D. (Quite Evidently Dramatic.)",
        "Ergo: {MONSTER}. Peer-reviewed by a pigeon.",
        "Therefore: {MONSTER}. Case closed, file stamped, snacks earned.",
        "Verdict: {MONSTER}. Agent K-9 has never been more sure of anything, except snacks.",
    ]

    static let humanConclusions = [
        "Therefore: CERTIFIED HUMAN. The Bureau is devastated.",
        "Conclusion: CERTIFIED HUMAN. Somebody fetch the Bureau a tissue.",
        "Ergo: CERTIFIED HUMAN. The radar hamster is very let down.",
    ]

    /// Five steps, ending in the verdict. Same verdict seed, same reasoning.
    public static func chain(for verdict: Verdict, evidence: ScanEvidence) -> [String] {
        var rng = SeededRandom(seed: verdict.seed ^ 0x2EA5_0111)
        func pick<T>(_ items: [T]) -> T { items[Int(rng.next() % UInt64(items.count))] }
        let monster = verdict.monster
        let isHuman = monster == .human
        let habit = pick(habits[monster] ?? habits[.human]!)
        // What they're wearing is funnier than the battery, so it gets picked more.
        let all = facts(evidence)
        let worn = all.filter { $0.phrase.hasPrefix("the ") && !$0.phrase.hasPrefix("the moon") }
        let fact = !worn.isEmpty && rng.unit() < 0.6 ? pick(worn) : pick(all)
        var stats = ["73.4%", "98.1%", "312%", "eleven out of ten", "a worrying 64%", "exactly 87.3%", "nearly 100%", "41.7% (rounded up)"]
        let stat = stats.remove(at: Int(rng.next() % UInt64(stats.count)))
        let stat2 = pick(stats)
        let name = isHuman ? "human" : monster.rawValue
        let title = isHuman ? "CERTIFIED HUMAN" : monster.rawValue.uppercased()

        func fill(_ template: String, clue: String = "") -> String {
            template
                .replacingOccurrences(of: "{x}", with: fact.phrase)
                .replacingOccurrences(of: "{habit}", with: habit.base)
                .replacingOccurrences(of: "{past}", with: habit.past)
                .replacingOccurrences(of: "{ing}", with: habit.ing)
                .replacingOccurrences(of: "{stat}", with: stat)
                .replacingOccurrences(of: "{stat2}", with: stat2)
                .replacingOccurrences(of: "{monsters}", with: plurals[monster] ?? name)
                .replacingOccurrences(of: "{monster}", with: name)
                .replacingOccurrences(of: "{MONSTER}", with: title)
                .replacingOccurrences(of: "{clue}", with: clue)
        }

        var steps = [fact.statement, fill(pick(leaps))]
        steps.append(fill(pick(isHuman ? humanBridges : bridges)))
        if !isHuman, verdict.wildcard == monster {
            steps.append(fill(pick(wildcardTwists)))
        } else if let clue = corroborating(verdict.clues, besides: fact) {
            steps.append(fill(pick(isHuman ? humanCorroborations : corroborations), clue: clue))
        }
        steps.append(fill(pick(isHuman ? humanConclusions : conclusions)))
        return steps.map(capitalisedFirst)
    }

    /// A clue for step 4 that doesn't just repeat step 1 (real clues first).
    static func corroborating(_ clues: [Clue], besides fact: Fact) -> String? {
        func core(_ text: String) -> String {
            var t = text.lowercased()
            for article in ["a ", "an ", "the "] where t.hasPrefix(article) { t.removeFirst(article.count) }
            return t
        }
        let seen = core(fact.phrase)
        let fresh = clues.filter { !seen.contains(core($0.evidence)) && !core($0.evidence).contains(seen) }
        return (fresh.first { !$0.isAnomaly } ?? fresh.first)?.evidence
    }

    static func capitalisedFirst(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }
}
