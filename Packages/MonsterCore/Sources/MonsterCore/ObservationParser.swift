import Foundation

/// Turns model output into `SubjectObservations`, forgivingly.
///
/// Small models produce code fences, prose around the JSON, trailing commas,
/// curly quotes, synonyms ("grey", "blond", "glasses on") and the odd missing
/// key. Those are repaired or mapped to "unknown". Anything that still isn't
/// recognisable JSON is a failure, so the caller can retry once and then fall
/// back to Classic Mode (spec section 4.1).
public enum ObservationParser {
    public enum Failure: Error, Equatable {
        case empty
        case noJSONObject
        case invalidJSON
        /// Parsed, but fewer than `minimumKeys` of the seven keys were present.
        case tooFewKeys(found: Int)
    }

    public static let minimumKeys = 5

    public static func parse(_ raw: String) -> Result<SubjectObservations, Failure> {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return .failure(.noJSONObject)
        }
        let candidate = repair(String(text[start...end]))
        guard let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return .failure(.invalidJSON)
        }

        // Case- and separator-insensitive keys: "Hair Color", "hairColor", "hair-color".
        var fields: [String: Any] = [:]
        for (key, value) in dictionary { fields[normaliseKey(key)] = value }
        let keys = ["haircolor", "eyecolor", "shirtcolor", "ageband", "expression", "accessories", "backgroundhint"]
        let found = keys.filter { fields[$0] != nil }.count
        guard found >= minimumKeys else { return .failure(.tooFewKeys(found: found)) }

        var observations = SubjectObservations()
        observations.hairColor = hair(string(fields["haircolor"]))
        observations.eyeColor = eye(string(fields["eyecolor"]))
        observations.shirtColor = freeText(string(fields["shirtcolor"]), maxWords: 3)
        observations.ageBand = age(string(fields["ageband"]))
        observations.expression = expression(string(fields["expression"]))
        observations.accessories = accessories(fields["accessories"])
        observations.backgroundHint = freeText(string(fields["backgroundhint"]), maxWords: 4)
        return .success(observations)
    }

    // MARK: - Repairs

    static func repair(_ json: String) -> String {
        var s = json
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
        // Trailing commas before } or ].
        s = s.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
        return s
    }

    static func normaliseKey(_ key: String) -> String {
        key.lowercased().filter(\.isLetter)
    }

    static func string(_ value: Any?) -> String {
        switch value {
        case let s as String: return s
        case let a as [Any]: return a.compactMap { $0 as? String }.first ?? ""
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }

    static func token(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    // MARK: - Field mapping

    static func hair(_ raw: String) -> HairColor {
        let t = token(raw)
        if let exact = HairColor(rawValue: t) { return exact }
        let synonyms: [String: HairColor] = [
            "grey": .gray, "silver": .gray, "blond": .blonde, "light brown": .brown, "dark brown": .brown,
            "auburn": .red, "ginger": .red, "dyed": .dyedOther, "pink": .dyedOther, "blue": .dyedOther,
            "purple": .dyedOther, "green": .dyedOther, "covered": .hidden, "not visible": .hidden,
            "bald": .unknown, "none": .unknown,
        ]
        if let mapped = synonyms[t] { return mapped }
        // "dark brown hair" → brown
        for hair in [HairColor.black, .brown, .blonde, .red, .gray, .white] where t.contains(hair.rawValue) {
            return hair
        }
        return .unknown
    }

    static func eye(_ raw: String) -> EyeColor {
        let t = token(raw)
        if let exact = EyeColor(rawValue: t) { return exact }
        if t == "grey" { return .gray }
        for eye in [EyeColor.brown, .blue, .green, .hazel, .gray] where t.contains(eye.rawValue) { return eye }
        return .unknown
    }

    static func age(_ raw: String) -> AgeBand {
        let t = token(raw).replacingOccurrences(of: "'", with: "")
        if let exact = AgeBand(rawValue: t) { return exact }
        let synonyms: [String: AgeBand] = [
            "kid": .child, "toddler": .child, "teenager": .teen, "teens": .teen,
            "twenties": .twenties, "thirties": .thirties, "forties": .forties, "fifties": .fifties,
            "60": .sixtyPlus, "60s": .sixtyPlus, "senior": .sixtyPlus,
        ]
        if let mapped = synonyms[t] { return mapped }
        // "30-39", "about 35"
        if let first = t.split(whereSeparator: { !$0.isNumber }).first, let number = Int(first) {
            return band(for: number)
        }
        return .unknown
    }

    static func band(for years: Int) -> AgeBand {
        switch years {
        case ..<13: .child
        case ..<20: .teen
        case ..<30: .twenties
        case ..<40: .thirties
        case ..<50: .forties
        case ..<60: .fifties
        default: .sixtyPlus
        }
    }

    static func expression(_ raw: String) -> FaceExpression {
        let t = token(raw)
        if let exact = FaceExpression(rawValue: t) { return exact }
        let synonyms: [String: FaceExpression] = [
            "smile": .smiling, "happy": .smiling, "grinning": .smiling, "laughing": .smiling,
            "neutral": .serious, "calm": .serious, "stern": .serious,
            "shocked": .surprised, "amazed": .surprised, "tired": .sleepy, "yawning": .sleepy,
            "silly": .sillyFace, "silly face": .sillyFace, "goofy": .sillyFace, "funny face": .sillyFace,
            "tongue out": .sillyFace,
        ]
        return synonyms[t] ?? .unknown
    }

    static func accessories(_ value: Any?) -> [Accessory] {
        var items: [String] = []
        switch value {
        case let list as [Any]: items = list.compactMap { $0 as? String }
        case let s as String: items = s.split(whereSeparator: { $0 == "," || $0 == ";" }).map(String.init)
        default: break
        }
        let synonyms: [String: Accessory] = [
            "eyeglasses": .glasses, "spectacles": .glasses, "shades": .sunglasses, "cap": .hat,
            "beanie": .hat, "hoodie": .hood, "earphones": .headphones, "earbuds": .headphones,
            "earring": .earrings, "chain": .necklace, "face mask": .mask,
        ]
        var result: [Accessory] = []
        for item in items {
            let t = token(item)
            guard let accessory = Accessory(rawValue: t) ?? synonyms[t], accessory != .none,
                  !result.contains(accessory) else { continue }
            result.append(accessory)
        }
        return Array(result.prefix(3))
    }

    /// Short, letters-only free text that passes the kindness check, else "unknown".
    static func freeText(_ raw: String, maxWords: Int) -> String {
        let cleaned = raw
            .replacingOccurrences(of: #"[^A-Za-z ,'/-]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .prefix(maxWords)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,'/-"))
            .lowercased()
        guard !cleaned.isEmpty, ContentPolicy.isAllowed(cleaned) else { return "unknown" }
        return cleaned
    }
}
