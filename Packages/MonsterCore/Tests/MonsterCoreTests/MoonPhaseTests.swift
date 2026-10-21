import Foundation
import Testing
@testable import MonsterCore

@Suite("Moon phase")
struct MoonPhaseTests {
    static func utc(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)!
    }

    // Eclipse dates are easy to verify: lunar eclipses happen at full moon,
    // solar eclipses at new moon.
    static let fullMoons = [
        "2024-01-25T17:54:00Z",
        "2024-09-18T02:34:00Z", // partial lunar eclipse
        "2025-03-14T06:55:00Z", // total lunar eclipse
        "2026-03-03T11:38:00Z", // total lunar eclipse
    ]
    static let newMoons = [
        "2017-08-21T18:30:00Z", // total solar eclipse
        "2024-04-08T18:21:00Z", // total solar eclipse
    ]

    @Test("Known full moons are almost fully lit", arguments: fullMoons)
    func fullMoon(_ date: String) {
        let lit = MoonPhase.illumination(at: Self.utc(date))
        #expect(lit > 0.97, "illumination \(lit)")
        #expect(MoonPhase.name(at: Self.utc(date)) == "FULL MOON")
    }

    @Test("Known new moons are almost dark", arguments: newMoons)
    func newMoon(_ date: String) {
        let lit = MoonPhase.illumination(at: Self.utc(date))
        #expect(lit < 0.03, "illumination \(lit)")
        #expect(MoonPhase.name(at: Self.utc(date)) == "NEW MOON")
    }

    @Test("A week after new moon is about half lit")
    func firstQuarter() {
        let date = Self.utc("2024-04-08T18:21:00Z").addingTimeInterval(7.38 * 86_400)
        #expect(abs(MoonPhase.illumination(at: date) - 0.5) < 0.1)
    }

    @Test("Age wraps within one synodic month")
    func ageRange() {
        for offset in stride(from: -400.0, through: 400.0, by: 3.7) {
            let age = MoonPhase.age(at: Self.utc("2024-01-01T00:00:00Z").addingTimeInterval(offset * 86_400))
            #expect((0..<MoonPhase.synodicMonth).contains(age))
        }
    }

    @Test("Local minutes since midnight")
    func minutesSinceMidnight() throws {
        let tz = try #require(TimeZone(identifier: "Australia/Sydney"))
        // 2026-10-21 12:30 UTC = 23:30 in Sydney (AEDT, UTC+11).
        #expect(Measurements.minutesSinceMidnight(of: Self.utc("2026-10-21T12:30:00Z"), in: tz) == 23 * 60 + 30)
    }
}
