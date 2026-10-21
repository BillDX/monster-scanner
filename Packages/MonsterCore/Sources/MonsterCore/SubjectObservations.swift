import Foundation

// Descriptive readings about the subject. In Classic Mode they come from
// pixel sampling and Apple's Vision framework; from M2 the Qwen model fills
// them in. The JSON keys match the model prompt (spec section 4.1).
//
// Kindness rule (DECISIONS.md S-2): hair and eye colour are shown in the
// readout only. The verdict engine never scores them, except `hidden` and
// `dyed-other`, which are style choices.

public enum HairColor: String, Codable, CaseIterable, Sendable {
    case black, brown, blonde, red, gray, white
    case dyedOther = "dyed-other"
    case hidden, unknown
}

public enum EyeColor: String, Codable, CaseIterable, Sendable {
    case brown, blue, green, hazel, gray, unknown
}

public enum AgeBand: String, Codable, CaseIterable, Sendable {
    case child, teen
    case twenties = "20s"
    case thirties = "30s"
    case forties = "40s"
    case fifties = "50s"
    case sixtyPlus = "60+"
    case unknown
}

public enum FaceExpression: String, Codable, CaseIterable, Sendable {
    case smiling, serious, surprised, sleepy
    case sillyFace = "silly-face"
    case unknown
}

public enum Accessory: String, Codable, CaseIterable, Sendable {
    case glasses, sunglasses, hat, hood, headphones, earrings, necklace, scarf, mask, none
}

/// Rough indoor / outdoor guess from the background description.
public enum Setting: String, Codable, Sendable {
    case indoors, outdoors, unknown

    private static let outdoorWords: Set<String> = [
        "outdoor", "outdoors", "outside", "park", "street", "beach", "garden", "forest", "woods",
        "sky", "field", "mountain", "mountains", "lake", "river", "sea", "ocean", "yard", "trees",
        "tree", "snow", "road", "city", "cityscape", "festival", "campsite", "trail", "grass", "sunset",
        "parking", "skatepark", "amusement",
    ]
    private static let indoorWords: Set<String> = [
        "indoor", "indoors", "inside", "room", "kitchen", "office", "bedroom", "bathroom", "bar",
        "restaurant", "cafe", "living", "hallway", "classroom", "car", "home", "house", "studio",
        "library", "shop", "store", "gym", "party", "couch", "sofa", "wall", "ceiling",
        "interior", "dining", "nightclub",
    ]

    public init(hint: String) {
        let words = hint.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        if words.contains(where: Self.outdoorWords.contains) {
            self = .outdoors
        } else if words.contains(where: Self.indoorWords.contains) {
            self = .indoors
        } else {
            self = .unknown
        }
    }
}

public struct SubjectObservations: Codable, Sendable, Equatable {
    public var hairColor: HairColor
    public var eyeColor: EyeColor
    /// Short colour name, e.g. "navy blue". Free text when it comes from the model.
    public var shirtColor: String
    public var ageBand: AgeBand
    public var expression: FaceExpression
    public var accessories: [Accessory]
    /// Up to four words, e.g. "city park at night".
    public var backgroundHint: String

    // Fun, kind free text from the AI observer (DECISIONS.md D-021). Never
    // scored by the verdict engine; shown in the reveal and narrated.
    // Each field passed the kindness check, or is nil / empty.

    /// A kind, funny take on the expression: "grinning like they found free cake".
    public var expressionRead: String?
    /// Up to 3 short things seen: "red bobble hat", "thumbs up".
    public var funDetails: [String]
    /// One silly, make-believe line: "radiates the calm of a wizard on holiday".
    public var vibe: String?

    enum CodingKeys: String, CodingKey {
        case hairColor = "hair_color"
        case eyeColor = "eye_color"
        case shirtColor = "shirt_color"
        case ageBand = "age_band"
        case expression
        case accessories
        case backgroundHint = "background_hint"
        case expressionRead = "expression_read"
        case funDetails = "fun_details"
        case vibe
    }

    public init(
        hairColor: HairColor = .unknown,
        eyeColor: EyeColor = .unknown,
        shirtColor: String = "unknown",
        ageBand: AgeBand = .unknown,
        expression: FaceExpression = .unknown,
        accessories: [Accessory] = [],
        backgroundHint: String = "unknown",
        expressionRead: String? = nil,
        funDetails: [String] = [],
        vibe: String? = nil
    ) {
        self.hairColor = hairColor
        self.eyeColor = eyeColor
        self.shirtColor = shirtColor
        self.ageBand = ageBand
        self.expression = expression
        self.accessories = accessories
        self.backgroundHint = backgroundHint
        self.expressionRead = expressionRead
        self.funDetails = funDetails
        self.vibe = vibe
    }

    /// Tolerant decoding: the fun fields are optional, so older saved data
    /// (and Classic Mode) still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hairColor = try c.decodeIfPresent(HairColor.self, forKey: .hairColor) ?? .unknown
        eyeColor = try c.decodeIfPresent(EyeColor.self, forKey: .eyeColor) ?? .unknown
        shirtColor = try c.decodeIfPresent(String.self, forKey: .shirtColor) ?? "unknown"
        ageBand = try c.decodeIfPresent(AgeBand.self, forKey: .ageBand) ?? .unknown
        expression = try c.decodeIfPresent(FaceExpression.self, forKey: .expression) ?? .unknown
        accessories = try c.decodeIfPresent([Accessory].self, forKey: .accessories) ?? []
        backgroundHint = try c.decodeIfPresent(String.self, forKey: .backgroundHint) ?? "unknown"
        expressionRead = try c.decodeIfPresent(String.self, forKey: .expressionRead)
        funDetails = try c.decodeIfPresent([String].self, forKey: .funDetails) ?? []
        vibe = try c.decodeIfPresent(String.self, forKey: .vibe)
    }

    public static let unknown = SubjectObservations()

    /// Accessories without the "none" placeholder.
    public var wornAccessories: Set<Accessory> {
        Set(accessories).subtracting([.none])
    }

    public var shirtFamily: ColorFamily { ColorFamily(name: shirtColor) }

    public var setting: Setting { Setting(hint: backgroundHint) }
}
