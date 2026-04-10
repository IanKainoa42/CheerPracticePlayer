import Foundation

struct PracticeSection: Identifiable, Hashable {
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
}
