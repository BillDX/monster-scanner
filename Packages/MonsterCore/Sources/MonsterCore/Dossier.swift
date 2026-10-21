import Foundation

/// Everything a dossier writer needs. The verdict and clues come from code;
/// a writer (templates now, the model from M3) only supplies the words.
public struct DossierInput: Sendable, Equatable {
    public var monster: Monster
    /// Evidence phrases for `{clue_1}`…`{clue_3}`.
    public var clueEvidence: [String]
    public var shirtColor: String
    public var confidenceText: String
    public var caseNumber: String
    public var trueAgeYears: Int
    /// Picks the template; comes from the verdict seed.
    public var seed: UInt64

    public init(verdict: Verdict, observations: SubjectObservations) {
        monster = verdict.monster
        clueEvidence = verdict.clues.map(\.evidence)
        shirtColor = observations.shirtColor
        confidenceText = verdict.confidenceText
        caseNumber = verdict.caseNumber
        trueAgeYears = verdict.trueAgeYears
        seed = verdict.seed
    }

    public init(
        monster: Monster, clueEvidence: [String], shirtColor: String, confidenceText: String,
        caseNumber: String, trueAgeYears: Int, seed: UInt64
    ) {
        self.monster = monster
        self.clueEvidence = clueEvidence
        self.shirtColor = shirtColor
        self.confidenceText = confidenceText
        self.caseNumber = caseNumber
        self.trueAgeYears = trueAgeYears
        self.seed = seed
    }
}

public struct DossierTemplate: Codable, Sendable, Equatable {
    public let text: String
    public let action: String
}

/// A rendered dossier.
public struct Dossier: Sendable, Equatable {
    public let body: String
    public let recommendedAction: String

    public var fullText: String { "\(body)\n\nRecommended action: \(recommendedAction)" }

    public var wordCount: Int {
        fullText.split(whereSeparator: { $0.isWhitespace }).count
    }
}

/// The hand-written template library (Classic Mode, and the fallback whenever
/// the model fails). Loaded from `dossiers.json`.
public struct DossierLibrary: Sendable {
    public let templates: [Monster: [DossierTemplate]]

    private struct File: Decodable {
        let version: Int
        let monsters: [String: [DossierTemplate]]
    }

    public init(jsonData: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: jsonData)
        var templates: [Monster: [DossierTemplate]] = [:]
        for (key, list) in file.monsters {
            guard let monster = Monster(rawValue: key) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown monster \(key)"))
            }
            templates[monster] = list
        }
        self.templates = templates
    }

    /// The library bundled with MonsterCore.
    public static let bundled: DossierLibrary = {
        guard let url = Bundle.module.url(forResource: "dossiers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let library = try? DossierLibrary(jsonData: data) else {
            preconditionFailure("dossiers.json is missing or invalid")
        }
        return library
    }()

    /// Picks a template using the seed and fills the slots.
    public func write(_ input: DossierInput) -> Dossier {
        let list = templates[input.monster] ?? []
        guard !list.isEmpty else {
            return Dossier(body: "Subject classified: \(input.monster.verdictTitle).", recommendedAction: "Scan again.")
        }
        // Use different bits from the verdict engine's first draws.
        let index = Int((input.seed >> 17) % UInt64(list.count))
        return Self.render(list[index], with: input)
    }

    public static func render(_ template: DossierTemplate, with input: DossierInput) -> Dossier {
        Dossier(body: fill(template.text, input), recommendedAction: fill(template.action, input))
    }

    static func fill(_ text: String, _ input: DossierInput) -> String {
        let clues = input.clueEvidence + Array(repeating: "an unexplained reading", count: max(0, 3 - input.clueEvidence.count))
        let shirt = ColorFamily(name: input.shirtColor) == .unknown ? "classified-colour" : input.shirtColor
        let verdictWord = input.monster == .human ? "certified human" : input.monster.rawValue
        return text
            .replacingOccurrences(of: "{verdict}", with: verdictWord)
            .replacingOccurrences(of: "{clue_1}", with: clues[0])
            .replacingOccurrences(of: "{clue_2}", with: clues[1])
            .replacingOccurrences(of: "{clue_3}", with: clues[2])
            .replacingOccurrences(of: "{shirt_color}", with: shirt)
            .replacingOccurrences(of: "{confidence}", with: input.confidenceText)
            .replacingOccurrences(of: "{case_number}", with: input.caseNumber)
            .replacingOccurrences(of: "{true_age}", with: String(input.trueAgeYears))
    }
}
