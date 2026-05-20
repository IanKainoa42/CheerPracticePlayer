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
    private(set) var isPaused = false
    /// Cumulative reps attempted per block this session. Persists when the user jumps around.
    private(set) var repsAttempted: [UUID: Int] = [:]
    /// Playback rate multiplier. Mirrors the engine's rate so the UI can observe it.
    private(set) var playbackRate: Float = 1.0

    static let availablePlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]

    /// Minimum fraction of a section that must be played before the rep counts as attempted.
    static let repCompletionThreshold: Double = 0.75

    private let audioPlayer: AudioPlaybackControlling
    private var countdownTimer: Timer?
    private var sessionTimer: Timer?
    private(set) var playbackEndTimer: Timer?
    private var playheadTimer: Timer?
    private var currentSegmentEndTime: TimeInterval = 0

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

    // MARK: - Playback Rate

    func cyclePlaybackRate() {
        let rates = Self.availablePlaybackRates
        let currentIndex = rates.firstIndex(where: { abs($0 - playbackRate) < 0.001 }) ?? rates.firstIndex(of: 1.0) ?? 0
        let nextIndex = (currentIndex + 1) % rates.count
        setPlaybackRate(rates[nextIndex])
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        audioPlayer.rate = rate

        // If currently playing a section, reschedule the auto-advance timer for the new rate.
        if case .playing = runner.phase, !isPaused, playbackEndTimer != nil {
            let remainingAudio = max(currentSegmentEndTime - audioPlayer.currentTime, 0)
            let realDelay = remainingAudio / Double(max(rate, 0.01))
            cancelPlaybackEnd()
            if realDelay > 0 {
                playbackEndTimer = Timer.scheduledTimer(withTimeInterval: realDelay, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.onSectionPlaybackFinished() }
                }
            }
        }
    }

    // MARK: - Playback Controls

    func playCurrentBlock() {
        if isPaused {
            resumePlayback()
            return
        }
        guard prepareCurrentBlockForPlayback() else { return }
        runner.start()
        playCurrentSection()
        startSessionTimer()
        keepScreenAwake(true)
    }

    func resumePlayback() {
        guard isPaused else { return }
        let remainingAudio = max(currentSegmentEndTime - audioPlayer.currentTime, 0)
        
        guard remainingAudio > 0.01 else {
            isPaused = false
            onSectionPlaybackFinished()
            return
        }

        audioPlayer.rate = playbackRate
        audioPlayer.resumeUntil(remainingDuration: remainingAudio)
        isPaused = false
        cancelPlaybackEnd()
        let realDelay = remainingAudio / Double(max(playbackRate, 0.01))
        if realDelay > 0 {
            playbackEndTimer = Timer.scheduledTimer(withTimeInterval: realDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.onSectionPlaybackFinished() }
            }
        }
        startPlayheadTimer()
        startSessionTimer()
        audioStatus = "Playing"
        keepScreenAwake(true)
    }

    func restartBlock() {
        guard prepareCurrentBlockForPlayback() else { return }
        stopCountdown()
        runner.restartBlock()
        playCurrentSection()
    }

    func skipBlock() {
        creditCurrentRepIfThresholdMet()
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
        isPaused = false
        audioStatus = "Ready — \(runner.currentBlock?.title ?? "Block \(index + 1)")"
    }

    func pausePlayback() {
        stopCountdown()
        cancelPlaybackEnd()
        stopPlayheadTimer()
        stopSessionTimer()
        audioPlayer.pause()
        isPaused = true
        audioStatus = "Paused"
    }

    func beginBreak() {
        cancelPlaybackEnd()
        audioPlayer.pause()
        runner.beginBreak()
        audioStatus = phaseDescription
        startCountdown()
    }

    /// Tapping/scrubbing the timeline selects a block by index and starts playback from the
    /// beginning of its section. Prevents scrubbing to arbitrary times outside programmed sections.
    func selectBlock(at index: Int) {
        guard session.blocks.indices.contains(index) else { return }
        creditCurrentRepIfThresholdMet()
        stopCountdown()
        cancelPlaybackEnd()
        runner.jumpToBlock(index: index)
        guard prepareCurrentBlockForPlayback() else { return }
        runner.start()
        playCurrentSection()
        startSessionTimer()
        keepScreenAwake(true)
    }

    /// Fast-forward through an active break and immediately start the next rep.
    func skipBreak() {
        stopCountdown()
        cancelPlaybackEnd()
        runner.completeBreak()
        guard prepareCurrentBlockForPlayback() else { return }
        playCurrentSection()
    }

    func resetSession() {
        stopCountdown()
        stopSessionTimer()
        stopPlayheadTimer()
        cancelPlaybackEnd()
        audioPlayer.pause()
        runner.resetSession()
        isPaused = false
        elapsedSessionTime = 0
        currentPlaybackTime = 0
        repsAttempted.removeAll()
        audioStatus = "Ready"
        keepScreenAwake(false)
    }

    // MARK: - Auto-Advance Flow

    /// Called when a section finishes playing. Triggers the rep → rest → next rep flow.
    private func onSectionPlaybackFinished() {
        guard runner.phase == .playing else { return }
        // Credit the rep only if at least the threshold fraction of the section played.
        creditCurrentRepIfThresholdMet()
        runner.finishRep()

        switch runner.phase {
        case .breakCountdown:
            audioStatus = phaseDescription
            startCountdown()

        case .playing:
            // No rest needed — play next rep immediately
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

    /// Credit the in-progress rep if the section has played past the completion threshold.
    /// Called on natural section completion and when the user navigates away mid-rep.
    private func creditCurrentRepIfThresholdMet() {
        guard case .playing = runner.phase else { return }
        guard let block = runner.currentBlock else { return }
        let sectionDuration = block.section.duration
        guard sectionDuration > 0 else { return }
        let playedAudio = audioPlayer.currentTime - block.section.startTime
        if playedAudio >= Self.repCompletionThreshold * sectionDuration {
            repsAttempted[block.id, default: 0] += 1
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

        let sectionDuration = block.section.duration
        guard sectionDuration > 0.01 else {
            onSectionPlaybackFinished()
            return
        }

        currentSegmentEndTime = block.section.endTime
        isPaused = false

        audioPlayer.rate = playbackRate
        audioPlayer.playSegment(
            startTime: block.section.startTime,
            endTime: block.section.endTime
        )
        audioStatus = "Playing \(block.section.name) — Rep \(runner.currentRep)/\(block.reps)"
        startPlayheadTimer()

        // Schedule auto-advance when the section finishes playing
        let realDelay = sectionDuration / Double(max(playbackRate, 0.01))
        if realDelay > 0 {
            playbackEndTimer = Timer.scheduledTimer(withTimeInterval: realDelay, repeats: false) { [weak self] _ in
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
            if secondsRemaining <= PracticeBlock.countdownTailSeconds {
                return "Get ready: \(secondsRemaining)"
            }
            return "Rest: \(secondsRemaining)s"
        case .complete:
            return "Session complete"
        }
    }
}
