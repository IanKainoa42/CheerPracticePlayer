import Foundation

struct PrototypeSession: Identifiable, Equatable {
    let id: UUID
    var teamName: String
    var mix: ImportedMix?
    var sections: [PracticeSection]
    var blocks: [PracticeBlock]

    var mixName: String {
        mix?.displayName ?? "No mix imported"
    }

    var mixDuration: TimeInterval {
        mix?.duration ?? inferredMixDuration
    }

    var inferredMixDuration: TimeInterval {
        let sectionDuration = sections.map(\.endTime).max() ?? 0
        let blockDuration = blocks.map(\.section.endTime).max() ?? 0
        return max(sectionDuration, blockDuration)
    }

    var totalEstimatedDuration: TimeInterval {
        PracticeBlock.totalEstimatedDuration(for: blocks)
    }

    mutating func attachMix(_ mix: ImportedMix) {
        self.mix = mix
        sections = sections.map { $0.clamped(to: mix.duration) }
        blocks = blocks.map { block in
            var updated = block
            updated.section = block.section.clamped(to: mix.duration)
            return updated
        }
    }

    mutating func addSection(_ section: PracticeSection) {
        sections.append(section.clamped(to: mixDuration))
    }

    mutating func upsertSection(_ section: PracticeSection) {
        let normalized = section.clamped(to: mixDuration)

        if let index = sections.firstIndex(where: { $0.id == normalized.id }) {
            sections[index] = normalized
        } else {
            sections.append(normalized)
        }

        blocks = blocks.map { block in
            guard block.section.id == normalized.id else { return block }
            var updated = block
            updated.section = normalized
            // Block title mirrors section name — no separate editor exists for block.title yet.
            updated.title = normalized.name
            return updated
        }
    }

    mutating func removeSection(id: UUID) {
        sections.removeAll { $0.id == id }
        blocks.removeAll { $0.section.id == id }
    }

    mutating func addBlock(for section: PracticeSection) {
        let normalizedSection = section.clamped(to: mixDuration)
        blocks.append(
            PracticeBlock(
                id: UUID(),
                title: normalizedSection.name,
                section: normalizedSection,
                reps: 3,
                restSeconds: 30,
                restartMode: .automatic
            )
        )
    }

    static let empty = PrototypeSession(
        id: UUID(),
        teamName: "My Team",
        mix: nil,
        sections: [],
        blocks: []
    )

    static let sample: PrototypeSession = {
        let tumble = PracticeSection(
            id: UUID(),
            name: "Tumble Section",
            type: .runningTumbling,
            startTime: 72,
            endTime: 98
        )
        let pyramid = PracticeSection(
            id: UUID(),
            name: "Pyramid",
            type: .pyramid,
            startTime: 110,
            endTime: 145
        )
        let fullOut = PracticeSection(
            id: UUID(),
            name: "Full Out",
            type: .fullOut,
            startTime: 0,
            endTime: 155
        )

        let mix = ImportedMix(
            id: UUID(),
            originalFileName: "Blackout Worlds Mix.m4a",
            fileName: "blackout-worlds-mix.m4a",
            duration: 155
        )

        return PrototypeSession(
            id: UUID(),
            teamName: "CFSD Blackout",
            mix: mix,
            sections: [tumble, pyramid, fullOut],
            blocks: [
                PracticeBlock(
                    id: UUID(),
                    title: "5x Tumbling",
                    section: tumble,
                    reps: 5,
                    restSeconds: 45,
                    restartMode: .automatic
                ),
                PracticeBlock(
                    id: UUID(),
                    title: "4x Pyramid",
                    section: pyramid,
                    reps: 4,
                    restSeconds: 60,
                    restartMode: .manual
                ),
                PracticeBlock(
                    id: UUID(),
                    title: "2x Full Out",
                    section: fullOut,
                    reps: 2,
                    restSeconds: 120,
                    restartMode: .automatic
                )
            ]
        )
    }()
}
