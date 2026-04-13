import Foundation

struct ImportedMix: Equatable, Hashable, Codable {
    let id: UUID
    var originalFileName: String
    var localPath: String
    var duration: TimeInterval

    var displayName: String {
        if originalFileName.isEmpty {
            return URL(fileURLWithPath: localPath).lastPathComponent
        }
        return originalFileName
    }

    var localURL: URL {
        URL(fileURLWithPath: localPath)
    }
}
