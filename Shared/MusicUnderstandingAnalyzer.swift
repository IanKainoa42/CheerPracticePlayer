import AVFoundation
import CoreMedia
import Foundation

/// Bridges Apple's Music Understanding framework (introduced WWDC 2026, iOS 27)
/// into a `BeatMap`. The framework analyzes audio entirely on-device.
///
/// IMPORTANT: This whole type is compiled only when the Music Understanding SDK
/// is present (`canImport`). On the current toolchain (Xcode 26.5 / iOS 26.5 SDK)
/// the module does not exist, so this code is skipped and analysis returns nil —
/// every beat-sync feature degrades to the existing wall-clock countdown.
///
/// The exact symbol names below (`MusicUnderstandingSession`, `RhythmResult`,
/// `.rhythm`) follow the WWDC 2026 session description and MUST be verified
/// against the real iOS 27 SDK headers once it is installed; they are isolated
/// here precisely so that verification touches one file.
#if canImport(MusicUnderstanding)
import MusicUnderstanding

@available(iOS 27.0, macCatalyst 27.0, *)
enum MusicUnderstandingAnalyzer {
    static func analyze(url: URL) async -> BeatMap? {
        let asset = AVURLAsset(url: url)
        do {
            let session = MusicUnderstandingSession(asset: asset)
            let result = try await session.analyze([.rhythm])
            guard let rhythm = result.rhythm else { return nil }
            let beats = rhythm.beats.map { $0.seconds }.filter { $0.isFinite }
            let bars = rhythm.bars.map { $0.seconds }.filter { $0.isFinite }
            guard !beats.isEmpty else { return nil }
            return BeatMap(
                bpm: rhythm.beatsPerMinute,
                beatTimes: beats.sorted(),
                barTimes: bars.sorted()
            )
        } catch {
            return nil
        }
    }
}
#endif
