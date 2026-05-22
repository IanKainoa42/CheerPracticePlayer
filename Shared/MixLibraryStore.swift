import Foundation

@Observable
final class MixLibraryStore {
    private(set) var mixes: [SavedMix] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("CheerPracticePlayer", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("mix-library.json")
        }
        load()
    }

    // MARK: - Public API

    func save(_ mix: ImportedMix, sections: [PracticeSection]) {
        if let index = mixes.firstIndex(where: { $0.mix.id == mix.id }) {
            mixes[index].sections = sections
        } else {
            let entry = SavedMix(
                id: UUID(),
                mix: mix,
                sections: sections,
                dateAdded: Date()
            )
            mixes.insert(entry, at: 0)
        }
        persist()
    }

    func updateSections(for mixID: UUID, sections: [PracticeSection]) {
        guard let index = mixes.firstIndex(where: { $0.mix.id == mixID }) else { return }
        mixes[index].sections = sections
        persist()
    }

    func remove(id: UUID) {
        mixes.removeAll { $0.id == id }
        persist()
    }

    func savedMix(for mixID: UUID) -> SavedMix? {
        mixes.first { $0.mix.id == mixID }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([SavedMix].self, from: data)
            // Drop entries whose audio file no longer exists on disk. App
            // container path can shift across reinstalls and the user has no
            // reason to see — let alone tap — a row that cannot play.
            let surviving = decoded.filter { FileManager.default.fileExists(atPath: $0.mix.localPath) }
            mixes = surviving
            if surviving.count != decoded.count {
                persist()
            }
        } catch {
            // Don't silently overwrite a corrupt-but-present library on the next
            // persist(); rename it aside so the user (or a future migration) can
            // recover it. Then start clean.
            backupCorruptFile()
            mixes = []
        }
    }

    private func backupCorruptFile() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = fileURL.appendingPathExtension("bak-\(stamp)")
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(mixes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
