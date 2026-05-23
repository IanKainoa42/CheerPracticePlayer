import Foundation

struct ImportedMix: Equatable, Hashable, Codable {
    let id: UUID
    var originalFileName: String
    /// The relative name of the file within the app's imported mixes directory.
    /// Storing only the name avoids brittle absolute paths that change across app updates.
    var fileName: String
    var duration: TimeInterval

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
