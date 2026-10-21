import Testing
@testable import MonsterCore

/// Guards against one verdict taking over in real use (it happened: Robot
/// won nearly every daytime scan because its clues described any ordinary
/// photo). Uses a believable mix of party photos, by night and by day.
@Suite("Verdict balance on realistic photos")
struct BalanceTests {
    @Test("No verdict dominates, every verdict turns up", arguments: [false, true])
    func balanced(daytime: Bool) {
        let spread = Fixtures.spread(Fixtures.realistic(count: 5_000, daytime: daytime))
        print("SPREAD " + (daytime ? "DAY  " : "NIGHT") + " " + Monster.allCases.map {
            String(format: "%@ %.0f%%", $0.rawValue, (spread[$0] ?? 0) * 100)
        }.joined(separator: " · "))
        for monster in Monster.scorable {
            let share = spread[monster] ?? 0
            #expect(share <= 0.27, "\(monster) wins \(Int(share * 100))% of \(daytime ? "daytime" : "evening") scans")
            #expect(share >= 0.04, "\(monster) only wins \(Int(share * 100))% of \(daytime ? "daytime" : "evening") scans")
        }
        let human = spread[.human] ?? 0
        #expect((0.08...0.25).contains(human), "human verdict \(Int(human * 100))%")
    }

    @Test("An ordinary neutral face on a level head isn't automatically a robot")
    func ordinaryIsNotRobot() {
        // Serious face, head 1.5° off level, sharp-ish photo, grey shirt, indoors at lunchtime.
        let ordinary = Fixtures.evidence { m, o in
            o.expression = .serious; o.shirtColor = "gray"; o.backgroundHint = "office"
            m.headRollDegrees = 1.5; m.blurVariance = 800; m.minutesSinceMidnight = 13 * 60
        }
        let robots = (0..<100).filter { VerdictEngine.decide(ordinary, seed: Fixtures.seed($0)).monster == .robot }.count
        #expect(robots < 40, "robot \(robots)/100")
    }
}
