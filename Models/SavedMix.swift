import Foundation

struct SavedMix: Identifiable, Codable, Equatable {
    let id: UUID
    var mix: ImportedMix
    var sections: [PracticeSection]
    /// Per-mix block programming (reps, rest, restart mode). Optional in the
    /// on-disk JSON so older libraries (sections-only) still decode cleanly;
    /// in memory we always materialize an empty array when absent.
    var blocks: [PracticeBlock]
    var dateAdded: Date

    var displayName: String { mix.displayName }
    var duration: TimeInterval { mix.duration }
    var sectionCount: Int { sections.count }

    /// Estimated wall-clock time to run this mix's programmed blocks end to end.
    /// Matches the Builder's "Est" total so the Library can preview run length.
    var estimatedSessionDuration: TimeInterval {
        PracticeBlock.totalEstimatedDuration(for: blocks)
    }

    init(id: UUID, mix: ImportedMix, sections: [PracticeSection], blocks: [PracticeBlock] = [], dateAdded: Date) {
        self.id = id
        self.mix = mix
        self.sections = sections
        self.blocks = blocks
        self.dateAdded = dateAdded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.mix = try c.decode(ImportedMix.self, forKey: .mix)
        self.sections = try c.decode([PracticeSection].self, forKey: .sections)
        self.blocks = (try? c.decode([PracticeBlock].self, forKey: .blocks)) ?? []
        self.dateAdded = try c.decode(Date.self, forKey: .dateAdded)
    }
}
