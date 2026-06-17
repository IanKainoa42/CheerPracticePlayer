import Foundation

/// Single entry point the app uses to obtain a `BeatMap` for a mix. Hides the
/// availability gate so callers (import, lazy backfill) never reference the
/// iOS-27-only analyzer directly.
enum BeatMapService {
    /// True when on-device rhythm analysis is available on this OS + toolchain.
    static var isAvailable: Bool {
        #if canImport(MusicUnderstanding)
        if #available(iOS 27.0, macCatalyst 27.0, *) { return true }
        #endif
        return false
    }

    /// Analyzes the audio at `url`, returning a cached-ready `BeatMap`, or nil
    /// when analysis is unavailable or fails. Safe to call on any OS.
    static func analyze(url: URL) async -> BeatMap? {
        #if canImport(MusicUnderstanding)
        if #available(iOS 27.0, macCatalyst 27.0, *) {
            return await MusicUnderstandingAnalyzer.analyze(url: url)
        }
        #endif
        return nil
    }
}
