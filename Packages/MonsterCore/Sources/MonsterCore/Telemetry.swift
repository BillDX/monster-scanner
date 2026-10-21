import Foundation

/// Scrolling fake-but-real telemetry for the scanning sequence: every line
/// that shows a number shows a real measured value.
public enum Telemetry {
    /// Measurement lines, then observation lines.
    public static func lines(for e: ScanEvidence, moonName: String? = nil) -> [String] {
        measurementLines(for: e, moonName: moonName) + observationLines(for: e)
    }

    /// Lines from code measurements only (geometry, light, moon, time, battery).
    public static func measurementLines(for e: ScanEvidence, moonName: String? = nil) -> [String] {
        let m = e.measurements
        var lines: [String] = []

        lines.append("FACES IN FRAME: \(m.faceCount)" + (m.faceCount > 1 ? " (SCANNING LARGEST)" : ""))

        if let area = m.faceAreaFraction {
            let tag = area > 0.35 ? " (DANGEROUSLY CLOSE)" : area < 0.03 ? " (BARELY THERE)" : ""
            lines.append("SUBJECT SIZE: \(Fmt.pct(area)) OF FRAME\(tag)")
        }
        if let tilt = m.headTilt {
            let tag = tilt > 12 ? " (ANTENNA ALIGNMENT)" : tilt < 2 ? " (SUSPICIOUSLY LEVEL)" : ""
            lines.append("HEAD TILT: \(Fmt.deg(tilt))\(tag)")
        }
        if let yaw = m.headYawDegrees {
            lines.append("HEAD YAW: \(Fmt.deg(yaw))")
        }

        let light = m.brightness
        lines.append("LUMINANCE: \(Fmt.pct(light))" + (light < 0.22 ? " (LURKING CONDITIONS)" : light > 0.85 ? " (BLINDING)" : ""))
        lines.append("BLUR INDEX: \(Int(m.blurVariance))" + (m.isBlurry ? " (PHASING DETECTED)" : " (STABLE)"))

        let moon = m.moonIllumination
        let moonTag = moon > 0.85 ? "DANGER" : moon > 0.5 ? "RISING SUSPICION" : "CALM"
        lines.append("MOON PHASE: \(Fmt.pct(moon)) (\(moonTag))")
        if let moonName { lines.append("LUNAR STATUS: \(moonName)") }

        let hour = m.hour
        let timeTag = hour >= 21 || hour < 4 ? "NOCTURNAL" : hour < 8 ? "PRE-COFFEE" : hour >= 18 ? "DUSK PROTOCOL" : "DAYLIGHT"
        lines.append("LOCAL TIME: \(m.clockText) (\(timeTag))")

        if let battery = m.batteryLevel {
            lines.append("BATTERY: \(Fmt.pct(battery))" + (battery < 0.2 ? " (DRAINED BY VAMPIRES?)" : ""))
        } else {
            lines.append("BATTERY: UNREADABLE (SUSPICIOUS)")
        }
        return lines
    }

    /// Lines from the observations (Classic sampling or the AI observer).
    /// `prefix` marks who made them, e.g. "OBSERVER: ".
    public static func observationLines(for e: ScanEvidence, prefix: String = "") -> [String] {
        let m = e.measurements
        let o = e.observations
        var lines: [String] = []
        let family = o.shirtFamily
        if let hue = m.shirtHueDegrees, family != .unknown {
            lines.append(prefix + "SHIRT HUE: \(Int(hue.rounded()))° (SUSPICIOUSLY \(family.displayName.uppercased()))")
        } else if family != .unknown {
            lines.append(prefix + "SHIRT: \(Fmt.shirt(e).uppercased()) (NOTED)")
        }
        if o.expression != .unknown {
            lines.append(prefix + "EXPRESSION: \(o.expression.rawValue.uppercased())")
        }
        if o.setting != .unknown {
            lines.append(prefix + "SETTING: \(o.setting.rawValue.uppercased())")
        }
        let worn = o.wornAccessories.subtracting([.mask])
        if !worn.isEmpty {
            let names = Accessory.allCases.filter(worn.contains).map { $0.rawValue.uppercased() }
            lines.append(prefix + "ACCESSORIES: \(names.joined(separator: ", "))")
        }
        if let read = o.expressionRead {
            lines.append(prefix + "MOOD READING: \(read.uppercased())")
        }
        for detail in o.funDetails {
            lines.append(prefix + "NOTED: \(detail.uppercased())")
        }
        return lines
    }

    /// Lines shown while measurements are still being taken.
    public static let warmUp: [String] = [
        "INITIALISING BUREAU SCANNER…",
        "CROSS-REFERENCING CRYPTID DATABASE…",
        "CALIBRATING ECTOPLASM SENSORS…",
        "ECTOPLASM: TRACE AMOUNTS",
        "CONSULTING THE MOON…",
        "CHECKING FOR REFLECTIONS…",
    ]
}
