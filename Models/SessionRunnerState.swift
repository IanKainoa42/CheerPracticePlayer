import Foundation

enum LivePlaybackPhase: Equatable {
    case idle
    case playing
    case breakCountdown(secondsRemaining: Int)
    case waitingForManualStart
    case complete

    /// True when this break-countdown phase is in the final "get ready" tail.
    var isCountdownTail: Bool {
        if case .breakCountdown(let remaining) = self {
            return remaining <= PracticeBlock.countdownTailSeconds
        }
        return false
    }
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
            // More reps remaining — increment immediately
            currentRep += 1
            if block.restSeconds > 0 {
                phase = .breakCountdown(secondsRemaining: block.restSeconds)
            } else {
                phase = postRestPhase(for: block)
            }
        } else {
            // Last rep of this block — advance to next block
            let nextIndex = currentBlockIndex + 1
            if template.blocks.indices.contains(nextIndex) {
                currentBlockIndex = nextIndex
                currentRep = 1
                let nextBlock = template.blocks[nextIndex]
                let nextRest = nextBlock.restSeconds
                if nextRest > 0 {
                    phase = .breakCountdown(secondsRemaining: nextRest)
                } else {
                    phase = postRestPhase(for: nextBlock)
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
                // Break finished — currentRep was already advanced in finishRep.
                if let block = currentBlock {
                    phase = postRestPhase(for: block)
                } else {
                    phase = .complete
                }
                return false
            }

        default:
            return false
        }
    }

    mutating func beginBreak() {
        guard let block = currentBlock else { return }
        if currentRep < block.reps {
            currentRep += 1
        }
        phase = .breakCountdown(secondsRemaining: block.restSeconds)
    }

    /// Fast-forward through the current break: transition to `.playing`.
    /// currentRep is already advanced when the break began.
    mutating func completeBreak() {
        guard case .breakCountdown = phase else { return }
        phase = .playing
    }

    /// Fast-forward the rest countdown to a specific seconds-remaining value.
    /// Used by slide-to-skip to jump into the GET READY tail without skipping
    /// the warning. No-op outside of `.breakCountdown` or if the target value
    /// would extend (not shorten) the remaining time.
    mutating func fastForwardBreak(toRemaining seconds: Int) {
        guard case .breakCountdown(let remaining) = phase else { return }
        guard seconds < remaining, seconds > 0 else { return }
        phase = .breakCountdown(secondsRemaining: seconds)
    }

    /// Promote a parked manual-start phase directly into `.playing` without
    /// touching currentRep. Used by slide-to-skip so the coach's slide doubles
    /// as the manual "go" — the next rep starts automatically when the countdown
    /// completes, instead of waiting for a separate tap.
    mutating func startFromManualWait() {
        guard case .waitingForManualStart = phase else { return }
        phase = .playing
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

    private func postRestPhase(for block: PracticeBlock) -> LivePlaybackPhase {
        block.restartMode == .automatic ? .playing : .waitingForManualStart
    }
}
