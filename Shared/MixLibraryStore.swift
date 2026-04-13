import Foundation

@Observable
final class MixLibraryStore {
    private(set) var mixes: [SavedMix] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CheerPracticePlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("mix-library.json")
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
        mixes = (try? JSONDecoder().decode([SavedMix].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(mixes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
