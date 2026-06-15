import Foundation

struct ImportedMix: Equatable, Hashable, Codable {
    let id: UUID
    var originalFileName: String
    /// The relative name of the file within the app's imported mixes directory.
    /// Storing only the name avoids brittle absolute paths that change across app updates.
    var fileName: String
    var duration: TimeInterval
    /// Cached on-device rhythm analysis (Music Understanding, iOS 27+). Optional so
    /// older libraries and mixes imported on pre-iOS-27 toolchains decode cleanly;
    /// nil means beat-sync features fall back to wall-clock timing.
    var beatMap: BeatMap?

    /// Explicit init keeps the `beatMap`-less call sites (imports, tests) compiling
    /// while the synthesized `Codable` still treats the optional key as absent → nil.
    init(
        id: UUID,
        originalFileName: String,
        fileName: String,
        duration: TimeInterval,
        beatMap: BeatMap? = nil
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.fileName = fileName
        self.duration = duration
        self.beatMap = beatMap
    }

    var displayName: String {
        if originalFileName.isEmpty {
            return fileName
        }
        return originalFileName
    }

    var localURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("CheerPracticePlayer", isDirectory: true)
            .appendingPathComponent("ImportedMixes", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
