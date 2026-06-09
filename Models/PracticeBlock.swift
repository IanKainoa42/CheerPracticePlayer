import Foundation

struct PracticeBlock: Identifiable, Hashable, Codable {
    enum RestartMode: String, CaseIterable, Codable {
        case automatic
        case manual

        var label: String {
            switch self {
            case .automatic: return "Auto"
            case .manual: return "Manual"
            }
        }

        var iconName: String {
            switch self {
            case .automatic: return "repeat"
            case .manual: return "hand.tap"
            }
        }

        var helpText: String {
            switch self {
            case .automatic:
                return "Starts the next rep automatically after the rest timer."
            case .manual:
                return "Runs the rest timer, then waits for you to tap the Live cue card before the next rep."
            }
        }
    }

    let id: UUID
    var title: String
    var section: PracticeSection
    var reps: Int
    /// Gap between reps (and before rep 1 of any block after the first).
    /// The last `PracticeBlock.countdownTailSeconds` of this gap are an audible/visible countdown.
    var restSeconds: Int
    var restartMode: RestartMode

    /// How many of the final seconds of `restSeconds` are surfaced as the "get ready" countdown.
    static let countdownTailSeconds: Int = 5

    var estimatedDuration: TimeInterval {
        let repCount = max(reps, 0)
        let sectionDuration = section.duration * Double(repCount)
        let restWindows = max(repCount - 1, 0)
        let restDuration = Double(restWindows * restSeconds)
        return sectionDuration + restDuration
    }

    /// Total estimated wall-clock time to run `blocks` back to back, including
    /// the rest gap before each block after the first. Shared by
    /// `PrototypeSession.totalEstimatedDuration` and `SavedMix` so the Builder
    /// and Library screens report identical numbers.
    static func totalEstimatedDuration(for blocks: [PracticeBlock]) -> TimeInterval {
        blocks.enumerated().reduce(0) { total, pair in
            let (index, block) = pair
            // External gap before the first rep of this block (skipped for the first block).
            let externalRest = index > 0 ? Double(block.restSeconds) : 0
            return total + block.estimatedDuration + externalRest
        }
    }
}
