import Foundation

enum LivePlaybackPhase: Equatable {
    case idle
    case playing
    case breakCountdown(secondsRemaining: Int)
    case leadIn(secondsRemaining: Int)
    case complete
}

struct SessionRunnerState {
    private(set) var template: PrototypeSession
    private(set) var currentBlockIndex: Int = 0
    private(set) var currentRep: Int = 0
    private(set) var phase: LivePlaybackPhase = .idle

    init(template: PrototypeSession) {
        self.template = template
    }

    var currentBlock: PracticeBlock? {
        guard template.blocks.indices.contains(currentBlockIndex) else { return nil }
        return template.blocks[currentBlockIndex]
    }

    var totalBlocks: Int {
        template.blocks.count
    }

    var isFirstBlock: Bool {
        currentBlockIndex == 0
    }

    var isLastBlock: Bool {
        currentBlockIndex >= template.blocks.count - 1
    }

    /// Overall session progress as a fraction 0...1
    var sessionProgress: Double {
        guard totalBlocks > 0 else { return 0 }
        let blockProgress = Double(currentBlockIndex) / Double(totalBlocks)
        guard let block = currentBlock, block.reps > 0 else { return blockProgress }
        let repFraction = Double(max(currentRep - 1, 0)) / Double(block.reps)
        let perBlockWeight = 1.0 / Double(totalBlocks)
        return blockProgress + repFraction * perBlockWeight
    }

    /// Elapsed reps across all blocks up to current position
    var totalRepsCompleted: Int {
        var count = 0
        for i in 0..<currentBlockIndex {
            count += template.blocks[i].reps
        }
        count += max(currentRep - 1, 0)
        return count
    }

    var totalReps: Int {
        template.blocks.reduce(0) { $0 + $1.reps }
    }

    mutating func syncTemplate(_ template: PrototypeSession) {
        self.template = template
        if !template.blocks.indices.contains(currentBlockIndex) {
            currentBlockIndex = 0
            currentRep = 0
            phase = .idle
        }
    }

    mutating func start() {
        guard currentBlock != nil else {
            phase = .complete
            return
        }
        currentRep = max(currentRep, 1)
        phase = .playing
    }

    mutating func advance() {
        guard let block = currentBlock else {
            phase = .complete
            return
        }

        if phase == .idle {
            start()
            return
        }

        if currentRep < block.reps {
            currentRep += 1
            phase = .playing
            return
        }

        let nextIndex = currentBlockIndex + 1
        if template.blocks.indices.contains(nextIndex) {
            currentBlockIndex = nextIndex
            currentRep = 1
            phase = .playing
        } else {
            phase = .complete
        }
    }

    mutating func finishRep() {
        guard let block = currentBlock else { return }

        if currentRep < block.reps {
            // More reps remaining — go to break
            if block.restSeconds > 0 {
                phase = .breakCountdown(secondsRemaining: block.restSeconds)
            } else if block.leadInSeconds > 0 {
                phase = .leadIn(secondsRemaining: block.leadInSeconds)
            } else {
                currentRep += 1
                phase = .playing
            }
        } else {
            // Last rep of this block — advance to next block
            let nextIndex = currentBlockIndex + 1
            if template.blocks.indices.contains(nextIndex) {
                currentBlockIndex = nextIndex
                currentRep = 1
                if template.blocks[nextIndex].leadInSeconds > 0 {
                    phase = .leadIn(secondsRemaining: template.blocks[nextIndex].leadInSeconds)
                } else {
                    phase = .playing
                }
            } else {
                phase = .complete
            }
        }
    }

    mutating func tickCountdown() -> Bool {
        switch phase {
        case .breakCountdown(let remaining):
            if remaining > 1 {
                phase = .breakCountdown(secondsRemaining: remaining - 1)
                return true
            } else {
                // Break finished — lead-in or play
                guard let block = currentBlock else {
                    phase = .complete
                    return false
                }
                currentRep += 1
                if block.leadInSeconds > 0 {
                    phase = .leadIn(secondsRemaining: block.leadInSeconds)
                } else {
                    phase = .playing
                }
                return false
            }

        case .leadIn(let remaining):
            if remaining > 1 {
                phase = .leadIn(secondsRemaining: remaining - 1)
                return true
            } else {
                phase = .playing
                return false
            }

        default:
            return false
        }
    }

    mutating func beginBreak() {
        guard let block = currentBlock else { return }
        phase = .breakCountdown(secondsRemaining: block.restSeconds)
    }

    mutating func beginLeadIn() {
        guard let block = currentBlock else { return }
        phase = .leadIn(secondsRemaining: block.leadInSeconds)
    }

    mutating func restartBlock() {
        currentRep = 1
        phase = .playing
    }

    mutating func skipBlock() {
        let nextIndex = currentBlockIndex + 1
        if template.blocks.indices.contains(nextIndex) {
            currentBlockIndex = nextIndex
            currentRep = 1
            phase = .playing
        } else {
            phase = .complete
        }
    }

    mutating func previousBlock() {
        guard currentBlockIndex > 0 else {
            restartBlock()
            return
        }
        currentBlockIndex -= 1
        currentRep = 1
        phase = .playing
    }

    mutating func jumpToBlock(index: Int) {
        guard template.blocks.indices.contains(index) else { return }
        currentBlockIndex = index
        currentRep = 1
        phase = .idle
    }

    mutating func resetSession() {
        currentBlockIndex = 0
        currentRep = 0
        phase = .idle
    }
}
