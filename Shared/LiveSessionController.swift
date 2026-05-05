import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class LiveSessionController {
    private(set) var session: PrototypeSession
    private(set) var runner: SessionRunnerState
    private(set) var audioStatus: String = "Ready"
    private(set) var elapsedSessionTime: TimeInterval = 0
    private(set) var isScreenLocked = false
    private(set) var waveformSamples: [Float] = []
    private(set) var currentPlaybackTime: TimeInterval = 0

    private let audioPlayer: AudioPlaybackControlling
    private var countdownTimer: Timer?
    private var sessionTimer: Timer?
    private var playbackEndTimer: Timer?
    private var playheadTimer: Timer?

    init(session: PrototypeSession, audioPlayer: AudioPlaybackControlling = AudioPlaybackEngine()) {
        self.session = session
        self.runner = SessionRunnerState(template: session)
        self.audioPlayer = audioPlayer
    }

    func syncSession(_ session: PrototypeSession) {
        self.session = session
        runner.syncTemplate(session)
        audioStatus = session.mix == nil ? "Import a mix to enable playback" : "Ready"
        loadWaveformIfNeeded()
    }

    func seek(to time: TimeInterval) {
        audioPlayer.seek(to: time)
        currentPlaybackTime = time
    }

    // MARK: - Playback Controls

    func playCurrentBlock() {
        guard prepareCurrentBlockForPlayback() else { return }
        runner.start()
        playCurrentSection()
        startSessionTimer()
        keepScreenAwake(true)
    }

    func restartBlock() {
        guard prepareCurrentBlockForPlayback() else { return }
        stopCountdown()
        runner.restartBlock()
        playCurrentSection()
    }

    func skipBlock() {
        stopCountdown()
        runner.skipBlock()
        guard runner.phase != .complete else {
            audioPlayer.pause()
            audioStatus = "Session complete"
            stopSessionTimer()
            keepScreenAwake(false)
            return
        }
        guard prepareCurrentBlockForPlayback() else { return }
        playCurrentSection()
    }

    func previousBlock() {
        stopCountdown()
        runner.previousBlock()
        guard prepareCurrentBlockForPlayback() else { return }
        playCurrentSection()
    }

    func jumpToBlock(index: Int) {
        stopCountdown()
        runner.jumpToBlock(index: index)
        audioPlayer.pause()
        audioStatus = "Ready — \(runner.currentBlock?.title ?? "Block \(index + 1)")"
    }

    func pausePlayback() {
        stopCountdown()
        cancelPlaybackEnd()
        stopPlayheadTimer()
        audioPlayer.pause()
        audioStatus = "Paused"
    }

    func beginBreak() {
        cancelPlaybackEnd()
        audioPlayer.pause()
        runner.beginBreak()
        audioStatus = phaseDescription
        startCountdown()
    }

    func beginLeadIn() {
        cancelPlaybackEnd()
        audioPlayer.pause()
        runner.beginLeadIn()
        audioStatus = phaseDescription
        startCountdown()
    }

    func resetSession() {
        stopCountdown()
        stopSessionTimer()
        stopPlayheadTimer()
        cancelPlaybackEnd()
        audioPlayer.pause()
        runner.resetSession()
        elapsedSessionTime = 0
        currentPlaybackTime = 0
        audioStatus = "Ready"
        keepScreenAwake(false)
    }

    // MARK: - Auto-Advance Flow

    /// Called when a section finishes playing. Triggers the rep → break → lead-in → next rep flow.
    private func onSectionPlaybackFinished() {
        guard runner.phase == .playing else { return }
        runner.finishRep()

        switch runner.phase {
        case .breakCountdown:
            audioStatus = phaseDescription
            startCountdown()

        case .leadIn:
            audioStatus = phaseDescription
            startCountdown()

        case .playing:
            // No break or lead-in needed — play next rep immediately
            playCurrentSection()

        case .complete:
            audioPlayer.pause()
            stopPlayheadTimer()
            audioStatus = "Session complete 🎉"
            stopSessionTimer()
            keepScreenAwake(false)

        case .idle:
            break
        }
    }

    // MARK: - Countdown Timer

    private func startCountdown() {
        stopCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickCountdown()
            }
        }
    }

    private func tickCountdown() {
        let shouldContinue = runner.tickCountdown()
        audioStatus = phaseDescription

        if !shouldContinue {
            stopCountdown()
            // After countdown finishes, the runner transitions to .playing
            if runner.phase == .playing {
                guard prepareCurrentBlockForPlayback() else { return }
                playCurrentSection()
            }
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Session Timer

    private func startSessionTimer() {
        guard sessionTimer == nil else { return }
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSessionTime += 1
            }
        }
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // MARK: - Section Playback

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
        cancelPlaybackEnd()

        audioPlayer.playSegment(
            startTime: block.section.startTime,
            endTime: block.section.endTime
        )
        audioStatus = "Playing \(block.section.name) — Rep \(runner.currentRep)/\(block.reps)"
        startPlayheadTimer()

        // Schedule auto-advance when the section finishes playing
        let sectionDuration = block.section.duration
        if sectionDuration > 0 {
            playbackEndTimer = Timer.scheduledTimer(withTimeInterval: sectionDuration, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.onSectionPlaybackFinished()
                }
            }
        }
    }

    private func cancelPlaybackEnd() {
        playbackEndTimer?.invalidate()
        playbackEndTimer = nil
    }

    // MARK: - Playhead Timer

    private func startPlayheadTimer() {
        stopPlayheadTimer()
        playheadTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.currentPlaybackTime = self.audioPlayer.currentTime
            }
        }
    }

    private func stopPlayheadTimer() {
        playheadTimer?.invalidate()
        playheadTimer = nil
    }

    // MARK: - Waveform

    private func loadWaveformIfNeeded() {
        guard let mix = session.mix else {
            waveformSamples = []
            return
        }
        let url = mix.localURL
        Task {
            let samples = (try? await WaveformExtractor.extractSamples(from: url)) ?? []
            self.waveformSamples = samples
        }
    }

    // MARK: - Screen Lock

    private func keepScreenAwake(_ awake: Bool) {
        isScreenLocked = awake
        UIApplication.shared.isIdleTimerDisabled = awake
    }

    // MARK: - Phase Description

    private var phaseDescription: String {
        switch runner.phase {
        case .idle:
            return "Ready"
        case .playing:
            if let block = runner.currentBlock {
                return "Playing \(block.section.name) — Rep \(runner.currentRep)/\(block.reps)"
            }
            return "Playing"
        case .breakCountdown(let secondsRemaining):
            return "Break: \(secondsRemaining)s remaining"
        case .leadIn(let secondsRemaining):
            return "Lead-In: \(secondsRemaining)s"
        case .complete:
            return "Session complete"
        }
    }
}
