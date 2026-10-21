import Foundation

/// A silly, kind subspecies under each verdict: "VAMPIRE · Brunch Bat".
/// Picked by the verdict seed, so it changes with Second Opinion.
public enum Subspecies {
    public static let catalogue: [Monster: [String]] = [
        .vampire: [
            "Brunch Bat", "Count of the Snack Table", "Night-Shift Aristocrat", "Garlic-Averse Socialite",
            "Velvet Cape Enthusiast", "Sunscreen Ambassador (SPF 9000)", "Duke of Dramatic Entrances",
            "Midnight Tea Connoisseur",
        ],
        .alien: [
            "Exchange Student from Zorb-7", "Tourist from the Andromeda Gift Shop", "Undercover Space Intern",
            "Galactic Snack Inspector", "Lost Crop-Circle Artist", "Mothership Middle Manager",
            "Interstellar Selfie Researcher", "Professional Earthling Impersonator",
        ],
        .kaiju: [
            "Pocket-Sized City Stomper", "Harbour Hugger", "Gentle Skyscraper Nibbler", "Kaiju-in-Training",
            "Sunday Afternoon Stomper", "Lizard of Unusual Size (Gentle Edition)", "Coastal Nap Champion",
            "Titan of the Buffet",
        ],
        .werewolf: [
            "Full-Moon Frisbee Champion", "Weekend Howler", "Professional Stick Fetcher",
            "Lone Wolf (Very Social Edition)", "Moonlight Jogger", "Snack-Table Guardian",
            "Howl-Along Choir Lead", "Tennis Ball Detective",
        ],
        .zombie: [
            "Pre-Coffee Shuffler", "Brunch Zombie", "Snooze-Button Revenant", "Slipper-Wearing Undead",
            "Professional Napper", "Mild-Mannered Moaner", "Leftover-Pizza Seeker", "Monday Morning Edition",
        ],
        .robot: [
            "Model T-1000-Thank-You", "Polite Toaster Mk II", "Spreadsheet-Powered Android",
            "Unit 42 (Friendly Firmware)", "Beep-Boop Butler", "Cupboard Organiser 3000", "Wi-Fi Whisperer",
            "Chess Champion Bot",
        ],
        .ghost: [
            "Friendly Hallway Haunter", "Bedsheet Classic", "Professional Door Creaker",
            "Spooky Sleepover Specialist", "Background-of-Photos Specialist", "Teacup Rattler",
            "Very Polite Poltergeist", "Mist Enthusiast",
        ],
        .human: [
            "Regular Earthling (Standard Edition)", "Ordinary Mortal, Very Nice", "Homo Sapiens, Probably",
            "Certified Snack Enjoyer", "Disappointingly Normal Specimen", "Human (Factory Settings)",
            "Garden-Variety Person", "Earth Resident, Fully Licensed",
        ],
    ]

    public static func name(for monster: Monster, seed: UInt64) -> String {
        let list = catalogue[monster] ?? []
        guard !list.isEmpty else { return "" }
        // Different bits from the template and engine draws.
        return list[Int((seed >> 29) % UInt64(list.count))]
    }
}

/// Extra jokes for the boot screen and the scan, picked fresh each time.
public enum Jokes {
    public static let bootChecks: [String] = [
        "Calibrating ectoplasm sensors… OK",
        "Polishing garlic detectors… OK",
        "Aligning alien antenna array… OK",
        "Charging silver-bullet capacitors… OK",
        "Untangling ghost-detector cables… OK",
        "Feeding the radar hamster… OK",
        "Recalibrating the moon-o-meter… OK",
        "Defrosting the cryptid database… OK",
        "Teaching the scanner to say 'boo'… OK",
        "Checking mirrors for missing reflections… OK",
        "Restocking emergency garlic bread… OK",
        "Rebooting the kaiju early-warning pigeon… OK",
        "Dusting the UFO landing pad… OK",
        "Tuning the howl frequency filter… OK",
        "Waking the night-shift intern… OK (mostly)",
    ]

    public static let scanFlavour: [String] = [
        "SNIFFING FOR GARLIC RESISTANCE…",
        "COUNTING SHADOWS… 1… 2… HMM.",
        "CHECKING FOR ANTENNAE UNDER HATS…",
        "PINGING THE MOTHERSHIP…",
        "LISTENING FOR DISTANT HOWLS…",
        "MEASURING ECTOPLASM IN PARTS PER MILLION…",
        "CONSULTING THE BUREAU'S OLDEST FILING CABINET…",
        "ASKING THE RADAR HAMSTER FOR ITS OPINION…",
        "ENHANCE… ENHANCE… OK THAT'S ENOUGH ENHANCING.",
        "RULING OUT LARGE BUT POLITE LIZARDS…",
        "CHECKING FIRMWARE FOR BEEP-BOOP SIGNATURES…",
        "DETECTING SNACK CRAVINGS…",
    ]

    /// A few lines to pepper the scan with, chosen by the seed.
    public static func flavour(count: Int, seed: UInt64) -> [String] {
        var rng = SeededRandom(seed: seed ^ 0x5EED_F1A7)
        var pool = scanFlavour
        var picked: [String] = []
        for _ in 0..<min(count, pool.count) {
            picked.append(pool.remove(at: Int(rng.next() % UInt64(pool.count))))
        }
        return picked
    }
}
