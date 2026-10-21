import Foundation

/// Code-written jokes about things the observer spotted ("The top hat?
/// Possibly a disguised antenna."). The model sees; the code jokes
/// (DECISIONS.md D-022). Reliable, kind, and still personal to each photo.
public enum Exhibits {
    /// `{thing}` is the spotted item without a leading article ("top hat").
    public static let jokes: [Monster: [String]] = [
        .vampire: [
            "Exhibit: {thing}. Standard issue for anyone avoiding sunlight.",
            "Note the {thing}. A classic cape-adjacent accessory.",
            "The {thing}? Ideal for a dramatic midnight entrance.",
            "Spotted: {thing}. The Bureau suspects it doubles as a coffin pillow.",
            "{Thing}. Garlic-proof, according to our lab.",
            "The {thing} was carefully positioned to avoid every mirror in the room.",
            "Spotted: {thing}. Pairs beautifully with tomato juice.",
            "Exhibit: {thing}. Last fashionable in Transylvania, which is suspicious.",
        ],
        .alien: [
            "Exhibit: {thing}. Possibly a disguised antenna.",
            "The {thing}? A standard souvenir from the Andromeda gift shop.",
            "Spotted: {thing}. The mothership's dress code is very specific.",
            "Note the {thing}. Earthlings rarely wear theirs this convincingly.",
            "Exhibit: {thing}. Emits a faint beep on certain frequencies.",
            "The {thing} has been sent to the lab for being suspiciously intergalactic.",
            "Spotted: {thing}. A classic attempt to blend in with the locals.",
            "{Thing}. Our crop-circle experts are very excited.",
        ],
        .kaiju: [
            "Exhibit: {thing}. Tiny, by kaiju standards.",
            "The {thing}? Perfect for a gentle stroll across the harbour.",
            "Spotted: {thing}. The city planning committee has questions.",
            "Note the {thing}. Stomp-resistant, apparently.",
            "Exhibit: {thing}. Seismographs twitched when it appeared.",
            "The {thing} is clearly a souvenir from a model railway that had a very bad day.",
            "Spotted: {thing}. A classic disguise for something much, much larger.",
            "{Thing}. Roar-compatible.",
        ],
        .werewolf: [
            "Exhibit: {thing}. Suspiciously easy to fetch.",
            "The {thing}? Clearly a full-moon accessory.",
            "Spotted: {thing}. Not chewed. Yet. The Bureau is watching.",
            "Note the {thing}. Excellent for a midnight howl.",
            "Exhibit: {thing}. Smells faintly of tennis balls.",
            "The {thing} would survive a frisbee tournament.",
            "Spotted: {thing}. A perfect disguise, right up until the moon comes out.",
            "{Thing}. Zoomie-ready.",
        ],
        .zombie: [
            "Exhibit: {thing}. Last seen near the coffee machine.",
            "The {thing}? Standard issue for a dignified shuffle.",
            "Spotted: {thing}. Brunch-ready.",
            "Note the {thing}. Ideal for napping in.",
            "Exhibit: {thing}. Has clearly survived several snooze buttons.",
            "The {thing} suggests a long night and an even longer lie-in.",
            "Spotted: {thing}. The Bureau prescribes one large coffee.",
            "{Thing}. Groan-approved.",
        ],
        .robot: [
            "Exhibit: {thing}. Possibly a cooling vent.",
            "The {thing}? Factory-fitted, according to the serial number.",
            "Spotted: {thing}. Runs on AA batteries, probably.",
            "Note the {thing}. Requires a firmware update every Tuesday.",
            "Exhibit: {thing}. Arranged with suspicious, spreadsheet-level precision.",
            "The {thing} emits a polite beep when nobody's looking.",
            "Spotted: {thing}. Wi-Fi signal strength increased nearby.",
            "{Thing}. Approved by the Bureau's toaster division.",
        ],
        .ghost: [
            "Exhibit: {thing}. Slightly see-through in some lights.",
            "The {thing}? Floats when nobody's watching.",
            "Spotted: {thing}. Found in the background of several group photos from 1887.",
            "Note the {thing}. Rattles gently at midnight.",
            "Exhibit: {thing}. Pairs beautifully with a bedsheet.",
            "The {thing} caused a mysterious cold spot.",
            "Spotted: {thing}. Creaks like a haunted door.",
            "{Thing}. Certified spooky, but sweet.",
        ],
        .human: [
            "Exhibit: {thing}. Disappointingly ordinary.",
            "The {thing}? Bought in a regular shop by a regular human. Sigh.",
            "Spotted: {thing}. No secret compartments. We checked twice.",
            "Note the {thing}. Exactly what a normal person would own.",
            "Exhibit: {thing}. Zero ectoplasm detected.",
            "The {thing} failed every monster test the Bureau has.",
            "Spotted: {thing}. Our scanner yawned.",
            "{Thing}. Completely, tragically normal.",
        ],
    ]

    /// Things worth joking about, best first: the observer's spotted details,
    /// then accessories, then the shirt.
    public static func things(in o: SubjectObservations) -> [String] {
        var things = o.funDetails.map(clean)
        let accessoryNames: [Accessory: String] = [
            .glasses: "glasses", .sunglasses: "sunglasses", .hat: "hat", .hood: "hood", .headphones: "headphones",
            .earrings: "earrings", .necklace: "necklace", .scarf: "scarf",
        ]
        for accessory in Accessory.allCases where o.wornAccessories.contains(accessory) {
            guard let name = accessoryNames[accessory] else { continue } // never the mask
            if !things.contains(where: { $0.localizedCaseInsensitiveContains(name) }) { things.append(name) }
        }
        if ColorFamily(name: o.shirtColor) != .unknown { things.append("\(o.shirtColor.lowercased()) shirt") }
        var unique: [String] = []
        for thing in things where !thing.isEmpty && !unique.contains(thing) { unique.append(thing) }
        return unique
    }

    /// Up to `count` exhibit jokes, chosen by the seed, for different things.
    public static func lines(for monster: Monster, observations: SubjectObservations, seed: UInt64, count: Int = 2) -> [String] {
        var rng = SeededRandom(seed: seed ^ 0xE4_1B17)
        var pool = jokes[monster] ?? []
        return things(in: observations).prefix(count).compactMap { thing in
            guard !pool.isEmpty else { return nil }
            let template = pool.remove(at: Int(rng.next() % UInt64(pool.count)))
            let line = fill(template, thing: thing)
            return ContentPolicy.isAllowed(line, strict: false) ? line : nil
        }
    }

    static func fill(_ template: String, thing: String) -> String {
        let capitalised = thing.prefix(1).uppercased() + thing.dropFirst()
        return template
            .replacingOccurrences(of: "{Thing}", with: capitalised)
            .replacingOccurrences(of: "{thing}", with: thing)
    }

    /// "a top hat" → "top hat"; trims punctuation.
    static func clean(_ detail: String) -> String {
        var words = detail.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(separator: " ").map(String.init)
        if let first = words.first?.lowercased(), ["a", "an", "the", "some"].contains(first), words.count > 1 {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }
}
