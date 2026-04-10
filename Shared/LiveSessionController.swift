import Foundation
import Observation

@MainActor
@Observable
final class LiveSessionController {
    private(set) var session: PrototypeSession
    private(set) var runner: SessionRunnerState
    private(set) var audioStatus: String = "Ready"

    private let audioPlayer: AudioPlaybackControlling

    init(session: PrototypeSession, audioPlayer: AudioPlaybackControlling = AudioPlaybackEngine()) {
        self.session = session
        self.runner = SessionRunnerState(template: session)
        self.audioPlayer = audioPlayer
    }

    func syncSession(_ session: PrototypeSession) {
        self.session = session
        runner.syncTemplate(session)
        audioStatus = session.mix == nil ? "Import a mix to enable playback" : "Ready"
    }

    func playCurrentBlock() {
        guard prepareCurrentBlockForPlayback() else { return }
        runner.start()
        playCurrentSection()
    }

    func restartBlock() {
        guard prepareCurrentBlockForPlayback() else { return }
        runner.restartBlock()
        playCurrentSection()
    }

    func skipBlock() {
        runner.skipBlock()
        guard runner.phase != .complete else {
            audioPlayer.pause()
            audioStatus = "Session complete"
            return
        }
        guard prepareCurrentBlockForPlayback() else { return }
        playCurrentSection()
    }

    func pausePlayback() {
        audioPlayer.pause()
        audioStatus = "Paused"
    }

    func beginBreak() {
        runner.beginBreak()
        audioPlayer.pause()
        audioStatus = phaseDescription
    }

    func beginLeadIn() {
        runner.beginLeadIn()
        audioStatus = phaseDescription
    }

    private func prepareCurrentBlockForPlayback() -> Bool {
        guard let block = runner.currentBlock else {
            audioStatus = "No practice block selected"
            return false
        }

        guard let mix = session.mix else {
            audioStatus = "Import a mix before starting playback"
            return false
        }

        do {
            try audioPlayer.load(url: mix.localURL)
            audioStatus = "Loaded \(block.section.name)"
            return true
        } catch {
            audioStatus = error.localizedDescription
            return false
        }
    }

    private func playCurrentSection() {
        guard let block = runner.currentBlock else { return }
        audioPlayer.playSegment(
            startTime: block.section.startTime,
            endTime: block.section.endTime
        )
        audioStatus = "Playing \(block.section.name)"
    }

    private var phaseDescription: String {
        switch runner.phase {
        case .idle:
            return "Ready"
        case .playing:
            return "Playing"
        case .breakCountdown(let secondsRemaining):
            return "Break: \(secondsRemaining)s"
        case .leadIn(let secondsRemaining):
            return "Lead-In: \(secondsRemaining)s"
        case .complete:
            return "Session complete"
        }
    }
}
