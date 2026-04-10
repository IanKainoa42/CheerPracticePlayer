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
}
