import Foundation

/// On-device rhythm analysis result for a mix, produced by Apple's Music
/// Understanding framework (iOS 27+) and cached on `ImportedMix`.
///
/// Stores the *real* per-beat and per-bar onset times (not a synthetic grid) so
/// count-ins, the live 8-count readout, and beat/bar trim snapping all read the
/// same source of truth and survive tempo drift in stitched cheer mixes.
///
/// Cheer convention: an **8-count = 8 beats = 2 bars** in common 4/4 time. The
/// 8-count grid is anchored to the first detected bar downbeat (count "1").
struct BeatMap: Equatable, Hashable, Codable {
    /// Global tempo reported by analysis. Used as the fallback beat interval.
    var bpm: Double
    /// Absolute beat onset times in the mix, ascending seconds.
    var beatTimes: [TimeInterval]
    /// Absolute bar (downbeat) onset times in the mix, ascending seconds.
    var barTimes: [TimeInterval]

    /// Beats per cheer 8-count.
    static let beatsPerEightCount = 8

    var isEmpty: Bool { beatTimes.isEmpty }

    /// Average seconds between beats. Prefers the global tempo; falls back to the
    /// measured span across all beats when tempo is missing.
    var beatInterval: TimeInterval {
        if bpm > 0 { return 60.0 / bpm }
        guard beatTimes.count >= 2, let first = beatTimes.first, let last = beatTimes.last else { return 0 }
        return (last - first) / Double(beatTimes.count - 1)
    }

    /// Beat index that anchors count "1" of the 8-count grid: the beat nearest
    /// the first detected bar downbeat. Falls back to beat 0 when bars are absent.
    var anchorBeatIndex: Int {
        guard let firstBar = barTimes.first else { return 0 }
        return nearestBeatIndex(to: firstBar) ?? 0
    }

    // MARK: - Beat lookups

    /// Index of the beat closest to `time`, or nil when there are no beats.
    func nearestBeatIndex(to time: TimeInterval) -> Int? {
        guard !beatTimes.isEmpty else { return nil }
        let insertion = lowerBound(beatTimes, time)
        if insertion == 0 { return 0 }
        if insertion >= beatTimes.count { return beatTimes.count - 1 }
        let before = beatTimes[insertion - 1]
        let after = beatTimes[insertion]
        return (time - before) <= (after - time) ? insertion - 1 : insertion
    }

    /// Index of the last beat at or before `time` (floor), or nil when `time`
    /// precedes the first beat / there are no beats.
    func floorBeatIndex(at time: TimeInterval) -> Int? {
        guard !beatTimes.isEmpty else { return nil }
        // First index strictly after `time`; the floor is the one before it.
        let after = upperBound(beatTimes, time)
        return after == 0 ? nil : after - 1
    }

    // MARK: - 8-count

    /// The 8-count number (1-based) and beat-within-8 (1...8) at `time`.
    /// Returns nil when there is no beat data.
    func eightCount(at time: TimeInterval) -> (count: Int, beat: Int)? {
        guard let idx = floorBeatIndex(at: time) ?? nearestBeatIndex(to: time) else { return nil }
        let rel = idx - anchorBeatIndex
        let per = Self.beatsPerEightCount
        let count = Int(floor(Double(rel) / Double(per))) + 1
        let beat = ((rel % per) + per) % per + 1
        return (count, beat)
    }

    // MARK: - Snapping (used by beat/bar/8-count trim)

    /// Nearest beat onset time to `time`.
    func nearestBeatTime(to time: TimeInterval) -> TimeInterval? {
        guard let idx = nearestBeatIndex(to: time) else { return nil }
        return beatTimes[idx]
    }

    /// Nearest bar (downbeat) onset time to `time`.
    func nearestBarTime(to time: TimeInterval) -> TimeInterval? {
        nearestTime(in: barTimes, to: time)
    }

    /// Nearest 8-count boundary time to `time` (every 8th beat from the anchor).
    func nearestEightCountTime(to time: TimeInterval) -> TimeInterval? {
        guard !beatTimes.isEmpty else { return nil }
        let anchor = anchorBeatIndex
        let per = Self.beatsPerEightCount
        let boundaries = stride(from: anchor % per, to: beatTimes.count, by: per).map { beatTimes[$0] }
        return nearestTime(in: boundaries, to: time)
    }

    // MARK: - Count-in tempo

    /// Local beat interval approaching `time`, measured across the up-to-`beats`
    /// onsets ending at the beat nearest `time`. Tracks tempo drift better than
    /// the global BPM; falls back to `beatInterval` when there isn't enough data.
    func localInterval(approaching time: TimeInterval, beats: Int) -> TimeInterval {
        guard beats > 0, beatTimes.count >= 2 else { return beatInterval }
        let idx = floorBeatIndex(at: time) ?? nearestBeatIndex(to: time) ?? 0
        let lo = max(idx - beats, 0)
        guard idx > lo else { return beatInterval }
        let span = beatTimes[idx] - beatTimes[lo]
        let interval = span / Double(idx - lo)
        return interval > 0 ? interval : beatInterval
    }

    // MARK: - Private helpers

    private func nearestTime(in times: [TimeInterval], to time: TimeInterval) -> TimeInterval? {
        guard !times.isEmpty else { return nil }
        let insertion = lowerBound(times, time)
        if insertion == 0 { return times[0] }
        if insertion >= times.count { return times[times.count - 1] }
        let before = times[insertion - 1]
        let after = times[insertion]
        return (time - before) <= (after - time) ? before : after
    }

    /// First index in the sorted array whose value is >= `value` (std lower_bound).
    private func lowerBound(_ array: [TimeInterval], _ value: TimeInterval) -> Int {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// First index in the sorted array whose value is > `value` (std upper_bound).
    private func upperBound(_ array: [TimeInterval], _ value: TimeInterval) -> Int {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid] <= value { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
