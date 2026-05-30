import Foundation

struct PracticeSection: Identifiable, Hashable, Codable {
    enum SectionType: String, CaseIterable, Codable {
        case warmup
        case jumps
        case standingTumbling
        case runningTumbling
        case pyramid
        case dance
        case fullOut
        case custom
    }

    let id: UUID
    var name: String
    var type: SectionType
    var startTime: TimeInterval
    var endTime: TimeInterval

    var duration: TimeInterval {
        max(endTime - startTime, 0)
    }

    /// Display-safe name: trimmed, with a fallback when the user clears the field
    /// to empty/whitespace. This is the single source of truth for the name shown
    /// in the Live tab — never read `name` directly for display.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Section" : trimmed
    }

    func clamped(to totalDuration: TimeInterval) -> PracticeSection {
        let boundedDuration = max(totalDuration, 0)
        let clampedStart = min(max(startTime, 0), boundedDuration)
        let clampedEnd = min(max(endTime, clampedStart), boundedDuration)

        return PracticeSection(
            id: id,
            name: name,
            type: type,
            startTime: clampedStart,
            endTime: clampedEnd
        )
    }

    static func blank(totalDuration: TimeInterval) -> PracticeSection {
        let boundedDuration = max(totalDuration, 0)
        let proposedEnd = min(32, Int(boundedDuration))

        return PracticeSection(
            id: UUID(),
            name: "New Section",
            type: .custom,
            startTime: 0,
            endTime: TimeInterval(proposedEnd)
        )
    }
}
