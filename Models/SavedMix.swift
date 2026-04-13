import Foundation

struct SavedMix: Identifiable, Codable, Equatable {
    let id: UUID
    var mix: ImportedMix
    var sections: [PracticeSection]
    var dateAdded: Date

    var displayName: String { mix.displayName }
    var duration: TimeInterval { mix.duration }
    var sectionCount: Int { sections.count }
}
