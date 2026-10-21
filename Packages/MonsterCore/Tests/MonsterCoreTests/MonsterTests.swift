import Testing
@testable import MonsterCore

@Suite("Monster catalogue")
struct MonsterTests {
    @Test("There are seven scorable monsters plus the human verdict")
    func catalogueSize() {
        #expect(Monster.allCases.count == 8)
        #expect(Monster.scorable.count == 7)
        #expect(!Monster.scorable.contains(.human))
    }

    @Test("Every verdict has a distinct emoji and a title", arguments: Monster.allCases)
    func hasPresentation(_ monster: Monster) {
        #expect(!monster.emoji.isEmpty)
        #expect(!monster.verdictTitle.isEmpty)
    }

    @Test("Emojis are unique")
    func emojisUnique() {
        let emojis = Monster.allCases.map(\.emoji)
        #expect(Set(emojis).count == emojis.count)
    }
}
