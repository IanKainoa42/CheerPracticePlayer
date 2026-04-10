import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum MixImportError: LocalizedError {
    case invalidDuration

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "The imported file did not report a usable duration."
        }
    }
}

struct MixImportService {
    static let supportedContentTypes: [UTType] = [
        .audio,
        .mp3,
        .mpeg4Audio,
        .wav,
        .aiff
    ]

    func importMix(from sourceURL: URL) async throws -> ImportedMix {
        let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationDirectory = try importedMixDirectory()
        let sanitizedBaseName = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "-")
        let destinationURL = destinationDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(sanitizedBaseName)")
            .appendingPathExtension(sourceURL.pathExtension)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let asset = AVURLAsset(url: destinationURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw MixImportError.invalidDuration
        }

        return ImportedMix(
            id: UUID(),
            originalFileName: sourceURL.lastPathComponent,
            localPath: destinationURL.path,
            duration: duration
        )
    }

    private func importedMixDirectory() throws -> URL {
        let baseDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = baseDirectory
            .appendingPathComponent("CheerPracticePlayer", isDirectory: true)
            .appendingPathComponent("ImportedMixes", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
