import Foundation

/// Where the accent click falls during a beat-synced count-in.
enum CountInAccent: String, Codable, CaseIterable, Hashable {
    /// Accent on count 1 only (once per 8-count).
    case downbeat
    /// Accent on counts 1 and 5 (twice per 8-count).
    case halfBar

    var label: String {
        switch self {
        case .downbeat: return "On 1"
        case .halfBar: return "On 1 & 5"
        }
    }
}

/// Timbre used for the count-in accent. Non-accented beats are always a soft tick.
enum CountInSound: String, Codable, CaseIterable, Hashable {
    case click
    case snare

    var label: String {
        switch self {
        case .click: return "Click"
        case .snare: return "Snare"
        }
    }
}

/// A single scheduled tick in a count-in.
struct CountInClick: Equatable {
    /// Seconds from the start of the count-in.
    var offset: TimeInterval
    /// Whether this tick is accented per the chosen `CountInAccent`.
    var isAccent: Bool
    /// Count number within the 8-count (1...8) for display.
    var beatNumber: Int
}

/// A pure, timer-free description of a beat-synced count-in leading into a
/// section's downbeat. The controller turns these offsets into scheduled
/// sounds; keeping the math here makes it unit-testable without audio or timers.
///
/// The N clicks are counts 1...N at the song's local tempo; the music resumes on
/// the *next* "1" at `totalDuration` (one interval after the final click), so the
/// throw lands on the downbeat — the cheer "5,6,7,8" feel.
struct CountInPlan: Equatable {
    var clicks: [CountInClick]
    /// When audio should resume, measured from the start of the count-in.
    var totalDuration: TimeInterval
    /// Beat interval used to space the clicks.
    var interval: TimeInterval

    /// Builds a plan, or nil when there is no usable beat data / no lead-in.
    static func make(
        beatMap: BeatMap,
        targetTime: TimeInterval,
        eightCounts: Int,
        accent: CountInAccent
    ) -> CountInPlan? {
        guard eightCounts > 0, !beatMap.beatTimes.isEmpty else { return nil }
        let n = eightCounts * BeatMap.beatsPerEightCount
        let interval = beatMap.localInterval(approaching: targetTime, beats: n)
        guard interval > 0 else { return nil }

        let per = BeatMap.beatsPerEightCount
        let clicks: [CountInClick] = (0..<n).map { k in
            let beatNumber = (k % per) + 1
            let isAccent: Bool
            switch accent {
            case .downbeat: isAccent = beatNumber == 1
            case .halfBar: isAccent = beatNumber == 1 || beatNumber == 5
            }
            return CountInClick(offset: Double(k) * interval, isAccent: isAccent, beatNumber: beatNumber)
        }
        return CountInPlan(clicks: clicks, totalDuration: Double(n) * interval, interval: interval)
    }
}
