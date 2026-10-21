import Foundation

/// Offline moon phase from the date alone (mean synodic month from a known
/// new moon). Accurate to within about a day, which is plenty for werewolves.
public enum MoonPhase {
    /// Mean length of a lunar cycle in days.
    public static let synodicMonth = 29.530588853
    /// A reference new moon: 2000-01-06 18:14 UTC (Julian Day 2451550.26).
    static let referenceNewMoonJD = 2451550.26

    /// Days since the most recent new moon, 0..<29.53.
    public static func age(at date: Date) -> Double {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let days = (julianDay - referenceNewMoonJD).truncatingRemainder(dividingBy: synodicMonth)
        return days < 0 ? days + synodicMonth : days
    }

    /// Fraction of the moon's disc that is lit, 0 (new) ... 1 (full).
    public static func illumination(at date: Date) -> Double {
        let angle = 2 * Double.pi * age(at: date) / synodicMonth
        return (1 - cos(angle)) / 2
    }

    /// A human name for the phase, for telemetry.
    public static func name(at date: Date) -> String {
        let fraction = age(at: date) / synodicMonth
        switch fraction {
        case ..<0.034, 0.966...: return "NEW MOON"
        case ..<0.216: return "WAXING CRESCENT"
        case ..<0.284: return "FIRST QUARTER"
        case ..<0.466: return "WAXING GIBBOUS"
        case ..<0.534: return "FULL MOON"
        case ..<0.716: return "WANING GIBBOUS"
        case ..<0.784: return "LAST QUARTER"
        default: return "WANING CRESCENT"
        }
    }
}
