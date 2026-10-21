import Foundation

/// The full clue table (spec section 4.2, expanded).
///
/// Allowed inputs: clothing colour, accessories, setting, time of day, moon,
/// battery, head pose, framing, and photo brightness/blur.
/// Never: hair or eye colour (except hidden/dyed, which are style choices),
/// skin, body shape, age, health. `mask` is deliberately unused because it can
/// be a health item.
enum ClueBook {
    static let rules: [ClueRule] = vampire + alien + kaiju + werewolf + zombie + robot + ghost

    // MARK: Vampire

    static let vampire: [ClueRule] = [
        ClueRule(
            id: "vampire.shirt", monster: .vampire, weight: 2,
            strength: { [.black, .red].contains($0.observations.shirtFamily) ? 1 : 0 },
            evidence: { Fmt.a("\(Fmt.shirt($0)) shirt") },
            quip: { "Wardrobe: \(Fmt.shirt($0)). Extremely cape-compatible." }
        ),
        ClueRule(
            id: "vampire.night", monster: .vampire, weight: 2,
            strength: { $0.measurements.hour >= 21 || $0.measurements.hour < 4 ? 1 : 0 },
            evidence: { Fmt.a("photo taken at \($0.measurements.clockText)") },
            quip: { "Photo taken at \($0.measurements.clockText). Prime nocturnal hours." }
        ),
        ClueRule(
            id: "vampire.shades", monster: .vampire, weight: 3,
            strength: {
                $0.observations.wornAccessories.contains(.sunglasses) && $0.observations.setting != .outdoors ? 1 : 0
            },
            evidence: { _ in "sunglasses indoors" },
            quip: { _ in "Sunglasses indoors. Avoiding the light, are we?" }
        ),
        ClueRule(
            id: "vampire.battery", monster: .vampire, weight: 2.5,
            strength: { ($0.measurements.batteryLevel ?? 1) < 0.2 ? 1 : 0 },
            evidence: { Fmt.a("phone battery at \(Fmt.pct($0.measurements.batteryLevel ?? 0))") },
            quip: { "Battery at \(Fmt.pct($0.measurements.batteryLevel ?? 0)). Life force drained." }
        ),
        ClueRule(
            id: "vampire.shadows", monster: .vampire, weight: 1.5,
            strength: { $0.measurements.brightness < 0.22 ? 1 : 0 },
            evidence: { _ in "a suspiciously shadowy room" },
            quip: { "Ambient light \(Fmt.pct($0.measurements.brightness)). Lurking-grade shadows." }
        ),
        ClueRule(
            id: "vampire.daylight", monster: .vampire, weight: 1,
            strength: {
                (9..<17).contains($0.measurements.hour) && $0.observations.setting == .indoors ? 1 : 0
            },
            evidence: { Fmt.a("suspicious indoor hideout at \($0.measurements.clockText)") },
            quip: { "Indoors at \($0.measurements.clockText) in broad daylight. Avoiding the sun?" }
        ),
        ClueRule(
            id: "vampire.collar", monster: .vampire, weight: 1.5,
            strength: { !$0.observations.wornAccessories.isDisjoint(with: [.scarf, .necklace]) ? 1 : 0 },
            evidence: { _ in "a very elegant neckline accessory" },
            quip: { _ in "Scarf or necklace detected. Elegance level: positively Transylvanian." }
        ),
    ]

    // MARK: Alien

    static let alien: [ClueRule] = [
        ClueRule(
            id: "alien.shirt", monster: .alien, weight: 2.5,
            strength: { [.green, .silver].contains($0.observations.shirtFamily) ? 1 : 0 },
            evidence: { Fmt.a("\(Fmt.shirt($0)) shirt") },
            quip: { "Shirt: \(Fmt.shirt($0)). Standard mothership issue." }
        ),
        ClueRule(
            id: "alien.loudshirt", monster: .alien, weight: 2,
            strength: { [.yellow, .purple, .pink, .orange].contains($0.observations.shirtFamily) ? 1 : 0 },
            evidence: { Fmt.a("dazzling \(Fmt.shirt($0)) shirt") },
            quip: { "Shirt: \(Fmt.shirt($0)). Clearly not from around here." }
        ),
        ClueRule(
            id: "alien.tilt", monster: .alien, weight: 3,
            strength: { Fmt.ramp($0.measurements.headTilt ?? 0, from: 12, to: 25) },
            evidence: { Fmt.a("\(Fmt.deg($0.measurements.headTilt ?? 0)) head tilt") },
            quip: { "Head tilt \(Fmt.deg($0.measurements.headTilt ?? 0)). Antenna alignment in progress." }
        ),
        ClueRule(
            id: "alien.centred", monster: .alien, weight: 2,
            strength: { ($0.measurements.faceCenterOffset ?? 1) < 0.04 ? 1 : 0 },
            evidence: { _ in "a perfectly centred pose" },
            quip: {
                "Centred to within \(Fmt.pct($0.measurements.faceCenterOffset ?? 0)) of the frame. No Earthling is that precise."
            }
        ),
        ClueRule(
            id: "alien.surprised", monster: .alien, weight: 2.5,
            strength: { $0.observations.expression == .surprised ? 1 : 0 },
            evidence: { _ in "a look of total surprise" },
            quip: { _ in "Expression: surprised. Possibly first contact." }
        ),
        ClueRule(
            id: "alien.visor", monster: .alien, weight: 1.5,
            strength: { $0.observations.wornAccessories.contains(.glasses) ? 1 : 0 },
            evidence: { _ in "a translator visor (glasses)" },
            quip: { _ in "Glasses detected. Universal translator visor?" }
        ),
        ClueRule(
            id: "alien.nightsky", monster: .alien, weight: 1.5,
            strength: {
                let h = $0.measurements.hour
                return $0.observations.setting == .outdoors && (h >= 20 || h < 5) ? 1 : 0
            },
            evidence: { _ in "an outdoor night sky" },
            quip: { _ in "Outdoors after dark. Waiting for a pickup?" }
        ),
    ]

    // MARK: Kaiju

    static let kaiju: [ClueRule] = [
        ClueRule(
            id: "kaiju.size", monster: .kaiju, weight: 3.5,
            strength: { Fmt.ramp($0.measurements.faceAreaFraction ?? 0, from: 0.35, to: 0.5) },
            evidence: { Fmt.a("looming close-up filling \(Fmt.pct($0.measurements.faceAreaFraction ?? 0)) of the frame") },
            quip: { "Subject fills \(Fmt.pct($0.measurements.faceAreaFraction ?? 0)) of the frame. Dangerously close to the city." }
        ),
        ClueRule(
            id: "kaiju.approach", monster: .kaiju, weight: 1.5,
            strength: {
                let a = $0.measurements.faceAreaFraction ?? 0
                return (0.22..<0.35).contains(a) ? 1 : 0
            },
            evidence: { _ in "a steady approach towards the camera" },
            quip: { "Subject fills \(Fmt.pct($0.measurements.faceAreaFraction ?? 0)) of the frame and closing. Evacuate the harbour." }
        ),
        ClueRule(
            id: "kaiju.shirt", monster: .kaiju, weight: 2,
            strength: { [.green, .gray].contains($0.observations.shirtFamily) ? 1 : 0 },
            evidence: { Fmt.a("\(Fmt.shirt($0)) shirt") },
            quip: { "Shirt: \(Fmt.shirt($0)). Scaly camouflage." }
        ),
        ClueRule(
            id: "kaiju.outdoors", monster: .kaiju, weight: 1.5,
            strength: { $0.observations.setting == .outdoors ? 1 : 0 },
            evidence: { _ in "plenty of open terrain" },
            quip: { "Setting: \($0.observations.backgroundHint). Plenty of room to stomp." }
        ),
        ClueRule(
            id: "kaiju.lunch", monster: .kaiju, weight: 1.5,
            strength: { (690..<840).contains($0.measurements.minutesSinceMidnight) ? 1 : 0 },
            evidence: { Fmt.a("lunchtime photo at \($0.measurements.clockText)") },
            quip: { "Photo taken at \($0.measurements.clockText). Lunchtime for giant lizards." }
        ),
        ClueRule(
            id: "kaiju.roar", monster: .kaiju, weight: 2.5,
            strength: { $0.observations.expression == .sillyFace ? 1 : 0 },
            evidence: { _ in "a roar-adjacent expression" },
            quip: { _ in "Expression: silly face. Roar rehearsal detected." }
        ),
    ]

    // MARK: Werewolf

    static let werewolf: [ClueRule] = [
        ClueRule(
            id: "werewolf.moon", monster: .werewolf, weight: 3.5,
            strength: { Fmt.ramp($0.measurements.moonIllumination, from: 0.85, to: 0.98) },
            evidence: { Fmt.a("\(Fmt.pct($0.measurements.moonIllumination)) full moon") },
            quip: { "Moon \(Fmt.pct($0.measurements.moonIllumination)) full. DANGER." }
        ),
        ClueRule(
            id: "werewolf.hood", monster: .werewolf, weight: 2.5,
            strength: { !$0.observations.wornAccessories.isDisjoint(with: [.hood, .hat]) ? 1 : 0 },
            evidence: { $0.observations.wornAccessories.contains(.hood) ? "a suspicious hood" : "a suspicious hat" },
            quip: {
                ($0.observations.wornAccessories.contains(.hood) ? "Hood" : "Hat") + " detected. Classic full-moon disguise."
            }
        ),
        ClueRule(
            id: "werewolf.evening", monster: .werewolf, weight: 1.5,
            strength: { (18..<23).contains($0.measurements.hour) ? 1 : 0 },
            evidence: { "an evening photo at \($0.measurements.clockText)" },
            quip: { "Evening hours (\($0.measurements.clockText)). The howling window opens." }
        ),
        ClueRule(
            id: "werewolf.flannel", monster: .werewolf, weight: 2,
            strength: {
                let name = $0.observations.shirtColor.lowercased()
                let woodsy = ["plaid", "flannel", "check", "tartan"].contains { name.contains($0) }
                return woodsy || [.brown, .orange].contains($0.observations.shirtFamily) ? 1 : 0
            },
            evidence: { Fmt.a("\(Fmt.shirt($0)) shirt") },
            quip: { "Shirt: \(Fmt.shirt($0)). Excellent forest camouflage." }
        ),
        ClueRule(
            id: "werewolf.hidden", monster: .werewolf, weight: 1,
            strength: { $0.observations.hairColor == .hidden ? 1 : 0 },
            evidence: { _ in "a carefully covered-up hairstyle" },
            quip: { _ in "Hairstyle: concealed. Grooming schedule classified." }
        ),
        ClueRule(
            id: "werewolf.prowl", monster: .werewolf, weight: 1.5,
            strength: {
                let h = $0.measurements.hour
                return $0.observations.setting == .outdoors && (h >= 19 || h < 5) ? 1 : 0
            },
            evidence: { _ in "a night-time outdoor setting" },
            quip: { _ in "Outdoors at night. Prime prowling territory." }
        ),
    ]

    // MARK: Zombie

    static let zombie: [ClueRule] = [
        ClueRule(
            id: "zombie.sleepy", monster: .zombie, weight: 3,
            strength: { $0.observations.expression == .sleepy ? 1 : 0 },
            evidence: { _ in "a deeply sleepy expression" },
            quip: { _ in "Expression: sleepy. Brain activity: buffering." }
        ),
        ClueRule(
            id: "zombie.dawn", monster: .zombie, weight: 3,
            strength: { (5..<8).contains($0.measurements.hour) ? 1 : 0 },
            evidence: { Fmt.a("photo taken at \($0.measurements.clockText)") },
            quip: { "Photo taken at \($0.measurements.clockText). Pre-coffee undead." }
        ),
        ClueRule(
            id: "zombie.slump", monster: .zombie, weight: 1.5,
            strength: { (14..<17).contains($0.measurements.hour) ? 1 : 0 },
            evidence: { "an afternoon-slump photo at \($0.measurements.clockText)" },
            quip: { "Photo taken at \($0.measurements.clockText). Afternoon slump detected." }
        ),
        ClueRule(
            id: "zombie.latenight", monster: .zombie, weight: 1.5,
            strength: { (1..<5).contains($0.measurements.hour) ? 1 : 0 },
            evidence: { Fmt.a("photo taken way past bedtime (\($0.measurements.clockText))") },
            quip: { "Photo taken at \($0.measurements.clockText). Way past bedtime. Shambling likely." }
        ),
        ClueRule(
            id: "zombie.dim", monster: .zombie, weight: 1.5,
            strength: { $0.measurements.brightness < 0.3 ? 1 : 0 },
            evidence: { _ in "crypt-level lighting" },
            quip: { "Ambient light \(Fmt.pct($0.measurements.brightness)). Crypt-level illumination." }
        ),
        ClueRule(
            id: "zombie.loll", monster: .zombie, weight: 1.5,
            strength: {
                let t = $0.measurements.headTilt ?? 0
                return t >= 6 && t <= 12 ? 1 : 0
            },
            evidence: { Fmt.a("\(Fmt.deg($0.measurements.headTilt ?? 0)) head loll") },
            quip: { "Head angle \(Fmt.deg($0.measurements.headTilt ?? 0)). Mild shamble detected." }
        ),
        ClueRule(
            id: "zombie.drab", monster: .zombie, weight: 1.5,
            strength: { [.gray, .brown, .beige].contains($0.observations.shirtFamily) ? 1 : 0 },
            evidence: { Fmt.a("\(Fmt.shirt($0)) shirt") },
            quip: { "Shirt: \(Fmt.shirt($0)). Very 'just dug my way out'." }
        ),
        ClueRule(
            id: "zombie.glance", monster: .zombie, weight: 1.5,
            strength: { abs($0.measurements.headYawDegrees ?? 0) > 25 ? 1 : 0 },
            evidence: { _ in "a distracted sideways glance" },
            quip: {
                "Head turned \(Fmt.deg(abs($0.measurements.headYawDegrees ?? 0))). Distracted by a distant snack?"
            }
        ),
    ]

    // MARK: Robot

    static let robot: [ClueRule] = [
        ClueRule(
            id: "robot.serious", monster: .robot, weight: 1.5,
            strength: { $0.observations.expression == .serious ? 1 : 0 },
            evidence: { _ in "a perfectly neutral expression" },
            quip: { _ in "Expression: serious. Emotion module not installed." }
        ),
        ClueRule(
            id: "robot.shirt", monster: .robot, weight: 1.5,
            strength: { [.blue, .white].contains($0.observations.shirtFamily) ? 1 : 0 },
            evidence: { Fmt.a("\(Fmt.shirt($0)) shirt") },
            quip: { "Shirt: \(Fmt.shirt($0)). Factory default finish." }
        ),
        ClueRule(
            id: "robot.headphones", monster: .robot, weight: 3,
            strength: { $0.observations.wornAccessories.contains(.headphones) ? 1 : 0 },
            evidence: { _ in "headphones (possibly a charging cable)" },
            quip: { _ in "Headphones detected. Possibly a charging cable." }
        ),
        ClueRule(
            id: "robot.level", monster: .robot, weight: 1.5,
            strength: {
                guard let t = $0.measurements.headTilt else { return 0 }
                return t < 1 ? 1 : 0
            },
            evidence: { Fmt.a("\(Fmt.deg($0.measurements.headTilt ?? 0)) head tilt") },
            quip: { "Head tilt \(Fmt.deg($0.measurements.headTilt ?? 0)). Suspiciously level. Gyroscope confirmed." }
        ),
        ClueRule(
            id: "robot.sharp", monster: .robot, weight: 1,
            strength: { $0.measurements.isRazorSharp ? 1 : 0 },
            evidence: { _ in "unnaturally crisp edges" },
            quip: { "Sharpness index \(Int($0.measurements.blurVariance)). Edges too crisp for organic matter." }
        ),
        ClueRule(
            id: "robot.earrings", monster: .robot, weight: 1.5,
            strength: { $0.observations.wornAccessories.contains(.earrings) ? 1 : 0 },
            evidence: { _ in "a pair of signal receivers (earrings)" },
            quip: { _ in "Earrings detected. Signal receivers online." }
        ),
    ]

    // MARK: Ghost

    static let ghost: [ClueRule] = [
        ClueRule(
            id: "ghost.shirt", monster: .ghost, weight: 3,
            strength: { $0.observations.shirtFamily == .white ? 1 : 0 },
            evidence: { _ in "a white shirt" },
            quip: { _ in "Shirt: white. Bedsheet-adjacent." }
        ),
        ClueRule(
            id: "ghost.light", monster: .ghost, weight: 2,
            strength: { $0.measurements.brightness < 0.15 || $0.measurements.brightness > 0.85 ? 1 : 0 },
            evidence: { $0.measurements.brightness < 0.5 ? "near-total darkness" : "blinding light" },
            quip: { "Light level \(Fmt.pct($0.measurements.brightness)). Ideal spectral conditions." }
        ),
        ClueRule(
            id: "ghost.blur", monster: .ghost, weight: 3,
            strength: { $0.measurements.isBlurry ? 1 : 0 },
            evidence: { _ in "a blurry, phasing image" },
            quip: { "Blur index \(Int($0.measurements.blurVariance)). Subject partially phased out of this dimension." }
        ),
        ClueRule(
            id: "ghost.soft", monster: .ghost, weight: 1.5,
            strength: { $0.measurements.blurVariance < 160 && !$0.measurements.isBlurry ? 1 : 0 },
            evidence: { _ in "a slightly soft-focus subject" },
            quip: { "Blur index \(Int($0.measurements.blurVariance)). Edges fading out of this dimension." }
        ),
        ClueRule(
            id: "ghost.faint", monster: .ghost, weight: 2,
            strength: {
                guard let a = $0.measurements.faceAreaFraction else { return 0 }
                return a < 0.03 ? 1 : 0
            },
            evidence: { _ in "a barely-there presence in the frame" },
            quip: { "Subject covers \(Fmt.pct($0.measurements.faceAreaFraction ?? 0)) of the frame. Fading from this plane." }
        ),
        ClueRule(
            id: "ghost.edge", monster: .ghost, weight: 2,
            strength: { ($0.measurements.faceCenterOffset ?? 0) > 0.18 ? 1 : 0 },
            evidence: { _ in "a subject drifting at the edge of the frame" },
            quip: { _ in "Subject drifting at the edge of the frame. Haunting the margins." }
        ),
        ClueRule(
            id: "ghost.witching", monster: .ghost, weight: 2,
            strength: { $0.measurements.hour < 3 ? 1 : 0 },
            evidence: { Fmt.a("photo taken at \($0.measurements.clockText)") },
            quip: { "Photo taken at \($0.measurements.clockText). The witching hour." }
        ),
    ]

    // MARK: Anomaly readings (used when fewer than three real clues fire)

    static let anomalies: [Monster: [(evidence: String, quip: String)]] = [
        .vampire: [
            ("an unexplained chill in the room", "ANOMALY: room temperature dipped 0.3°. Coincidence? The Bureau thinks not."),
            ("suspiciously low garlic levels", "ANOMALY: garlic levels in the area are suspiciously low."),
            ("a mirror that couldn't make up its mind", "ANOMALY: nearby mirror reflection inconclusive."),
            ("a distant flapping sound", "ANOMALY: audio sensors picked up distant flapping."),
        ],
        .alien: [
            ("a faint beeping on an unknown frequency", "ANOMALY: radio sweep found beeping on 1420 MHz."),
            ("traces of stardust", "ANOMALY: stardust particles detected in the air."),
            ("an unusual interest in the sky", "ANOMALY: attention drifted skyward three times during the scan."),
            ("a cosmic background hum", "ANOMALY: cosmic hum detected. Volume: suspicious."),
        ],
        .kaiju: [
            ("a faint rumbling underfoot", "ANOMALY: seismograph twitch recorded during the scan."),
            ("ripples in a nearby glass of water", "ANOMALY: ripples detected in a nearby glass of water."),
            ("a sudden pigeon evacuation", "ANOMALY: local pigeons have left the area."),
            ("an echo that sounded like a roar", "ANOMALY: echo analysis returned 62% roar."),
        ],
        .werewolf: [
            ("a far-off howl", "ANOMALY: audio sensors caught a far-off howl."),
            ("a missing tennis ball", "ANOMALY: a nearby tennis ball is unaccounted for."),
            ("a sudden urge for a walk", "ANOMALY: walk-urgency index elevated."),
            ("a stray tuft of mysterious fluff", "ANOMALY: mysterious fluff detected on the scanner lens."),
        ],
        .zombie: [
            ("an audible yawn", "ANOMALY: microphone registered a long, slow yawn."),
            ("a powerful craving for brunch", "ANOMALY: brunch-craving index off the charts."),
            ("a slow, shuffling rhythm", "ANOMALY: motion sensors report gentle shuffling."),
            ("a half-finished coffee nearby", "ANOMALY: coffee proximity alert triggered."),
        ],
        .robot: [
            ("a faint whirring sound", "ANOMALY: audio sensors report low whirring at 60 Hz."),
            ("an extremely tidy aura", "ANOMALY: tidiness field strength 98%."),
            ("a suspiciously strong Wi-Fi signal", "ANOMALY: a strong Wi-Fi signal followed the subject."),
            ("perfectly timed footsteps", "ANOMALY: footstep rhythm exactly 120 beats per minute."),
        ],
        .ghost: [
            ("a cold spot in the room", "ANOMALY: thermal sensors found a cold spot."),
            ("a door that creaked on its own", "ANOMALY: a door creaked. Nobody was near it."),
            ("a flicker in the lights", "ANOMALY: lights flickered during the scan."),
            ("a faint whisper of 'boo'", "ANOMALY: audio sensors picked up a faint 'boo'."),
        ],
    ]

    /// Reasons a subject came out human. Never about the person's body.
    static let humanReasons: [(evidence: String, quip: String)] = [
        ("zero capes, fangs or antennae", "No capes, fangs or antennae found in frame."),
        ("a shadow, a reflection and excellent manners", "Shadow: present. Reflection: present. Manners: excellent."),
        ("a normal garlic tolerance", "Garlic tolerance within the normal human range."),
        ("no reaction to the moon", "Moon reaction: none. Disappointing."),
        ("a passed silver-spoon test", "Subject passed the silver-spoon test."),
        ("zero matches in the cryptid database", "Bureau database: zero matching cryptids."),
    ]
}
