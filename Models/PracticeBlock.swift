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

    /// Length of the beat-synced count-in, in cheer 8-counts. 0 disables it.
    /// Only takes effect when the mix has a `BeatMap`; otherwise the legacy
    /// `countdownTailSeconds` second-by-second countdown is used.
    var leadInEightCounts: Int
    /// Timbre for the count-in accent.
    var countInSound: CountInSound
    /// Where the count-in accent falls.
    var countInAccent: CountInAccent

    /// How many of the final seconds of `restSeconds` are surfaced as the "get ready" countdown.
    static let countdownTailSeconds: Int = 5

    init(
        id: UUID,
        title: String,
        section: PracticeSection,
        reps: Int,
        restSeconds: Int,
        restartMode: RestartMode,
        leadInEightCounts: Int = 1,
        countInSound: CountInSound = .click,
        countInAccent: CountInAccent = .halfBar
    ) {
        self.id = id
        self.title = title
        self.section = section
        self.reps = reps
        self.restSeconds = restSeconds
        self.restartMode = restartMode
        self.leadInEightCounts = leadInEightCounts
        self.countInSound = countInSound
        self.countInAccent = countInAccent
    }

    // Custom decode so libraries saved before the count-in config existed still
    // load — the new keys default instead of throwing on a missing key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.section = try c.decode(PracticeSection.self, forKey: .section)
        self.reps = try c.decode(Int.self, forKey: .reps)
        self.restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        self.restartMode = try c.decode(RestartMode.self, forKey: .restartMode)
        self.leadInEightCounts = (try? c.decode(Int.self, forKey: .leadInEightCounts)) ?? 1
        self.countInSound = (try? c.decode(CountInSound.self, forKey: .countInSound)) ?? .click
        self.countInAccent = (try? c.decode(CountInAccent.self, forKey: .countInAccent)) ?? .halfBar
    }

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
