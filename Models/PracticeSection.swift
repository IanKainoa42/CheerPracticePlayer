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
