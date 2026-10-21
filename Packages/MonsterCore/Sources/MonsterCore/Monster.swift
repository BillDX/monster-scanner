/// Every verdict the scanner can reach. `human` is the "no monster cleared
/// the threshold" result.
public enum Monster: String, CaseIterable, Codable, Sendable {
    case vampire
    case alien
    case kaiju
    case werewolf
    case zombie
    case robot
    case ghost
    case human

    public var emoji: String {
        switch self {
        case .vampire: "🧛"
        case .alien: "👽"
        case .kaiju: "🦖"
        case .werewolf: "🐺"
        case .zombie: "🧟"
        case .robot: "🤖"
        case .ghost: "👻"
        case .human: "🧑"
        }
    }

    /// The text shown on the verdict card.
    public var verdictTitle: String {
        switch self {
        case .human: "CERTIFIED HUMAN… for now"
        default: rawValue.uppercased()
        }
    }

    /// All monsters the verdict engine can score (everything except `human`).
    public static var scorable: [Monster] {
        allCases.filter { $0 != .human }
    }
}
