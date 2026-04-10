import Foundation

struct PracticeBlock: Identifiable, Hashable {
    enum RestartMode: String, CaseIterable, Codable {
        case automatic
        case manual
    }

    let id: UUID
    var title: String
    var section: PracticeSection
    var reps: Int
    var restSeconds: Int
    var leadInSeconds: Int
    var restartMode: RestartMode
    var metronomeEnabled: Bool

    var estimatedDuration: TimeInterval {
        let repCount = max(reps, 0)
        let sectionDuration = section.duration * Double(repCount)
        let restWindows = max(repCount - 1, 0)
        let restDuration = Double(restWindows * restSeconds)
        let leadIns = Double(repCount * leadInSeconds)
        return sectionDuration + restDuration + leadIns
    }
}
