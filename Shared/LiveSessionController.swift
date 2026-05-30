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

    static let availablePlaybackRates: [Float] = [0.7, 0.8, 0.9, 1.0, 1.05, 1.10]

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
                playbackEndTimer = makeCommonModeTimer(after: realDelay) { [weak self] in
                    self?.onSectionPlaybackFinished()
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

        switch runner.phase {
        case .breakCountdown:
            // Tab-switch (or any pause) during a rest interval stopped the countdown
            // timer but preserved the seconds-remaining on the runner. Restart the
            // timer from the preserved value; do NOT touch audio.
            isPaused = false
            audioStatus = phaseDescription
            startCountdown()
            startSessionTimer()
            keepScreenAwake(true)
            return
        case .idle, .waitingForManualStart, .complete:
            // Nothing meaningful to resume — clear the flag so the next tap drives
            // a fresh play/restart from the card.
            isPaused = false
            return
        case .playing:
            break
        }

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
            playbackEndTimer = makeCommonModeTimer(after: realDelay) { [weak self] in
                self?.onSectionPlaybackFinished()
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
        audioStatus = "Ready — \(runner.currentBlock?.section.displayName ?? "Block \(index + 1)")"
    }

    func pausePlayback() {
        // Always stop audio; safe to call when nothing is playing.
        audioPlayer.pause()

        // Only transition into the "paused" UI state if there's actually a
        // session in flight. Otherwise tab-switches would set isPaused=true on
        // an idle controller, eating the first tap on the Live cue card.
        switch runner.phase {
        case .idle, .waitingForManualStart, .complete:
            return
        case .playing, .breakCountdown:
            break
        }

        stopCountdown()
        cancelPlaybackEnd()
        stopPlayheadTimer()
        stopSessionTimer()
        isPaused = true
        audioStatus = "Paused"
    }

    func beginBreak() {
        cancelPlaybackEnd()
        audioPlayer.pause()
        runner.beginBreak()
        audioStatus = phaseDescription
        
        // Handle immediate countdown/warning trigger when rest starts
        if case .breakCountdown(let remaining) = runner.phase {
            if remaining == 10 {
                SoundEffectsPlayer.shared.playDoubleBeep()
            } else if remaining <= PracticeBlock.countdownTailSeconds {
                SoundEffectsPlayer.shared.playBeep()
            }
        }
        
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

    /// Fast-forward the rest period to the GET READY warning tail (the last
    /// `PracticeBlock.countdownTailSeconds` seconds), so the audible/visible
    /// countdown still fires before the next rep. Used by the slide-to-skip
    /// gesture during rest — gives the coach a warning instead of an instant cut.
    func skipBreakToCountdownTail() {
        guard case .breakCountdown(let remaining) = runner.phase else { return }
        let tail = PracticeBlock.countdownTailSeconds
        // Already inside the warning tail — fall back to a full skip so the
        // user can still get out of the rest with a slide.
        guard remaining > tail else {
            skipBreak()
            return
        }
        runner.fastForwardBreak(toRemaining: tail)
        audioStatus = phaseDescription
        // Trigger the entry-to-tail double beep that would have fired had we
        // ticked there naturally; tickCountdown handles single beeps on subsequent ticks.
        if tail == 10 {
            SoundEffectsPlayer.shared.playDoubleBeep()
        } else if tail <= PracticeBlock.countdownTailSeconds {
            SoundEffectsPlayer.shared.playBeep()
        }
        // Countdown timer is already running from the original beginBreak path;
        // restart it to ensure a clean 1-second cadence from this moment.
        startCountdown()
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
        // Natural completion — the timer fired because we scheduled it for the
        // section's end, so credit the rep unconditionally (capped at block.reps).
        // We do NOT use the audio-currentTime threshold here because the engine
        // starts 0.5s early for the pre-roll fade-in, so currentTime is short by
        // half a second at this point — short sections would never credit.
        creditCurrentRep()
        runner.finishRep()

        switch runner.phase {
        case .breakCountdown:
            audioStatus = phaseDescription
            // Handle immediate countdown/warning trigger when rest starts
            if case .breakCountdown(let remaining) = runner.phase {
                if remaining == 10 {
                    SoundEffectsPlayer.shared.playDoubleBeep()
                } else if remaining <= PracticeBlock.countdownTailSeconds {
                    SoundEffectsPlayer.shared.playBeep()
                }
            }
            startCountdown()

        case .playing:
            // No rest needed — play next rep immediately
            playCurrentSection()

        case .waitingForManualStart:
            audioPlayer.pause()
            stopPlayheadTimer()
            audioStatus = phaseDescription

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
    /// Called when the user navigates away mid-rep (skip/select block).
    private func creditCurrentRepIfThresholdMet() {
        guard case .playing = runner.phase else { return }
        guard let block = runner.currentBlock else { return }
        let sectionDuration = block.section.duration
        guard sectionDuration > 0 else { return }
        let playedAudio = audioPlayer.currentTime - block.section.startTime
        if playedAudio >= Self.repCompletionThreshold * sectionDuration {
            incrementAttempted(for: block)
        }
    }

    /// Credit the current rep unconditionally (used on natural section completion).
    /// Capped at `block.reps` so re-runs of an in-progress block can't overflow the pips.
    private func creditCurrentRep() {
        guard let block = runner.currentBlock else { return }
        incrementAttempted(for: block)
    }

    private func incrementAttempted(for block: PracticeBlock) {
        let current = repsAttempted[block.id] ?? 0
        if current < block.reps {
            repsAttempted[block.id] = current + 1
        }
    }

    // MARK: - Countdown Timer

    private func startCountdown() {
        stopCountdown()
        countdownTimer = makeCommonModeTimer(after: 1.0, repeats: true) { [weak self] in
            self?.tickCountdown()
        }
    }

    private func tickCountdown() {
        let shouldContinue = runner.tickCountdown()
        audioStatus = phaseDescription

        if shouldContinue {
            // Play beeps on countdown ticks
            if case .breakCountdown(let remaining) = runner.phase {
                if remaining == 10 {
                    SoundEffectsPlayer.shared.playDoubleBeep()
                } else if remaining <= PracticeBlock.countdownTailSeconds {
                    SoundEffectsPlayer.shared.playBeep()
                }
            }
        }

        if !shouldContinue {
            stopCountdown()
            audioStatus = phaseDescription

            switch runner.phase {
            case .playing:
                guard prepareCurrentBlockForPlayback() else { return }
                playCurrentSection()
            case .waitingForManualStart:
                audioPlayer.pause()
                stopPlayheadTimer()
            case .idle, .breakCountdown, .complete:
                break
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
        sessionTimer = makeCommonModeTimer(after: 1.0, repeats: true) { [weak self] in
            self?.elapsedSessionTime += 1
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
            audioStatus = "Loaded \(block.section.displayName)"
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
        audioStatus = "Playing \(block.section.displayName) — Rep \(runner.currentRep)/\(block.reps)"
        startPlayheadTimer()

        // Schedule auto-advance when the section finishes playing. The engine
        // starts up to 0.5s early for the pre-roll fade-in, so match its actual
        // run time — otherwise the rest countdown kicks in while audio is still
        // playing the final half-second.
        let preRoll = min(block.section.startTime, AudioPlaybackEngine.preRollFadeSeconds)
        let realDelay = (sectionDuration + preRoll) / Double(max(playbackRate, 0.01))
        if realDelay > 0 {
            playbackEndTimer = makeCommonModeTimer(after: realDelay) { [weak self] in
                self?.onSectionPlaybackFinished()
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
        playheadTimer = makeCommonModeTimer(after: 0.1, repeats: true) { [weak self] in
            guard let self else { return }
            self.currentPlaybackTime = self.audioPlayer.currentTime
        }
    }

    /// Build a `Timer` and register it with the main RunLoop in `.common` mode so
    /// SwiftUI animations (which keep the run loop in tracking mode) cannot starve
    /// our timers. `Timer.scheduledTimer` registers in `.default` mode, which is
    /// preempted by ongoing UIKit/SwiftUI tracking — losing us the section-end
    /// callback during the pulse-ring animation on the cue card.
    private nonisolated func makeCommonModeTimer(
        after interval: TimeInterval,
        repeats: Bool = false,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            Task { @MainActor in action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
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
                return "Playing \(block.section.displayName) — Rep \(runner.currentRep)/\(block.reps)"
            }
            return "Playing"
        case .breakCountdown(let secondsRemaining):
            if secondsRemaining <= PracticeBlock.countdownTailSeconds {
                return "Get ready: \(secondsRemaining)"
            }
            return "Rest: \(secondsRemaining)s"
        case .waitingForManualStart:
            return "Ready for manual start"
        case .complete:
            return "Session complete"
        }
    }
}
