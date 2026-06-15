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
    /// Current count number (1...8) during a beat-synced count-in, else nil.
    /// Exposed for the Live readout.
    private(set) var countInBeat: Int?

    static let availablePlaybackRates: [Float] = [0.7, 0.8, 0.9, 1.0, 1.05, 1.10]

    /// Minimum fraction of a section that must be played before the rep counts as attempted.
    static let repCompletionThreshold: Double = 0.75

    private let audioPlayer: AudioPlaybackControlling
    private var countdownTimer: Timer?
    /// Precise timers driving an in-progress beat-synced count-in (one per click
    /// plus a finalize). Empty when no count-in is running.
    private var beatTimers: [Timer] = []
    private var beatCountInRunning = false
    private var sessionTimer: Timer?
    private(set) var playbackEndTimer: Timer?
    private var playheadTimer: Timer?
    private var currentSegmentEndTime: TimeInterval = 0
    /// Set true when the user slide-to-skips during a rest. Tells the countdown
    /// completion to auto-start the next rep even in Manual mode — the slide
    /// itself is the "go" signal, so a second tap is redundant.
    private var slideQueuedAutoStart = false
    /// Non-modal notice surfaced to the Live tab when the user edits the
    /// currently-active block (or its section) while a session is in flight.
    /// The in-flight rep keeps its original timing; the new values apply at
    /// the next rep. Auto-clears after a few seconds.
    private(set) var pendingEditNotice: String?
    private var editNoticeDismissTask: DispatchWorkItem?

    init(session: PrototypeSession, audioPlayer: AudioPlaybackControlling = AudioPlaybackEngine()) {
        self.session = session
        self.runner = SessionRunnerState(template: session)
        self.audioPlayer = audioPlayer
    }

    func syncSession(_ session: PrototypeSession) {
        // Snapshot the active block BEFORE the runner picks up the new template,
        // so we can detect mid-flight edits and surface a non-modal notice.
        let activePhaseBeforeSync = runner.phase
        let previousActiveBlock = runner.currentBlock

        self.session = session
        runner.syncTemplate(session)
        audioStatus = session.mix == nil ? "Import a mix to enable playback" : "Ready"
        loadWaveformIfNeeded()

        detectMidFlightEdit(
            activePhaseBefore: activePhaseBeforeSync,
            previousBlock: previousActiveBlock
        )
    }

    /// If a session was actively running (playing or in a rest countdown) and the
    /// user edited the in-flight block (trim handles / name / reps / rest /
    /// restart mode), surface a brief non-interfering notice telling them the
    /// change applies at the next rep — the current rep keeps its original
    /// schedule because the playback timer is already armed for that endTime.
    private func detectMidFlightEdit(
        activePhaseBefore: LivePlaybackPhase,
        previousBlock: PracticeBlock?
    ) {
        guard let previous = previousBlock else { return }
        switch activePhaseBefore {
        case .playing, .breakCountdown:
            break
        case .idle, .waitingForManualStart, .complete:
            return
        }
        guard let updated = session.blocks.first(where: { $0.id == previous.id }) else {
            // Block was deleted mid-flight — that's a structural change the runner
            // already routes via syncTemplate; no toast needed.
            return
        }
        guard updated != previous else { return }
        showEditNotice("Edit saved — applies at next rep")
    }

    private func showEditNotice(_ message: String) {
        editNoticeDismissTask?.cancel()
        pendingEditNotice = message
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pendingEditNotice == message {
                self.pendingEditNotice = nil
            }
        }
        editNoticeDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: task)
    }

    /// Public dismiss for the edit notice — e.g. tap-to-dismiss on the banner.
    func dismissEditNotice() {
        editNoticeDismissTask?.cancel()
        editNoticeDismissTask = nil
        pendingEditNotice = nil
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
            // Re-evaluate: restart either the 1s countdown or the beat count-in
            // (from the top) depending on whether this block is beat-synced.
            startBreakCountdownAudio()
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
        slideQueuedAutoStart = false
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
        slideQueuedAutoStart = false
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
        startBreakCountdownAudio()
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

        // Beat-synced blocks: the slide jumps straight into the musical count-in,
        // and (as below) doubles as the manual "go".
        if let plan = activeCountInPlan {
            slideQueuedAutoStart = true
            startBeatCountIn(plan)
            return
        }

        let tail = PracticeBlock.countdownTailSeconds
        // Already inside the warning tail — fall back to a full skip so the
        // user can still get out of the rest with a slide.
        guard remaining > tail else {
            skipBreak()
            return
        }
        runner.fastForwardBreak(toRemaining: tail)
        // Slide is the manual "go" — auto-start the next rep when the countdown
        // completes, even if the block is in Manual mode. Without this the coach
        // gets countdown beeps and then has to tap again to begin playback.
        slideQueuedAutoStart = true
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
        slideQueuedAutoStart = false
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
            startBreakCountdownAudio()

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
        // Hand off to the beat-synced count-in once the rest reaches the lead-in
        // window. The 1s countdown owns the long rest; the beat scheduler owns
        // the final musical count-in and the audio resume.
        if !beatCountInRunning,
           let plan = activeCountInPlan,
           case .breakCountdown(let remaining) = runner.phase,
           remaining <= Int(ceil(plan.totalDuration)) {
            startBeatCountIn(plan)
            return
        }

        let shouldContinue = runner.tickCountdown()
        audioStatus = phaseDescription

        if shouldContinue {
            // Legacy second-by-second beeps — only when this block is NOT beat-synced.
            if activeCountInPlan == nil, case .breakCountdown(let remaining) = runner.phase {
                playLegacyBreakBeep(remaining: remaining)
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
                if slideQueuedAutoStart {
                    // Slide-to-skip during rest already authorized the next rep.
                    // Promote the runner to .playing and start audio.
                    slideQueuedAutoStart = false
                    runner.startFromManualWait()
                    guard prepareCurrentBlockForPlayback() else { return }
                    playCurrentSection()
                } else {
                    audioPlayer.pause()
                    stopPlayheadTimer()
                }
            case .idle, .breakCountdown, .complete:
                break
            }
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        cancelBeatCountIn()
    }

    // MARK: - Beat-Synced Count-In

    /// The count-in plan for the current block, or nil when beat-sync doesn't
    /// apply (no analyzed beat map, or the block disables the lead-in). When nil,
    /// the controller uses the legacy second-by-second countdown everywhere.
    private var activeCountInPlan: CountInPlan? {
        guard let block = runner.currentBlock,
              block.leadInEightCounts > 0,
              let beatMap = session.mix?.beatMap, !beatMap.isEmpty else { return nil }
        return CountInPlan.make(
            beatMap: beatMap,
            targetTime: block.section.startTime,
            eightCounts: block.leadInEightCounts,
            accent: block.countInAccent
        )
    }

    /// Starts the appropriate audio for an active break countdown: the beat-synced
    /// count-in if we're already inside the lead-in window, otherwise the 1s
    /// countdown (legacy beeps fire only when the block isn't beat-synced).
    private func startBreakCountdownAudio() {
        guard case .breakCountdown(let remaining) = runner.phase else { return }
        if let plan = activeCountInPlan, remaining <= Int(ceil(plan.totalDuration)) {
            startBeatCountIn(plan)
            return
        }
        if activeCountInPlan == nil {
            playLegacyBreakBeep(remaining: remaining)
        }
        startCountdown()
    }

    private func playLegacyBreakBeep(remaining: Int) {
        if remaining == 10 {
            SoundEffectsPlayer.shared.playDoubleBeep()
        } else if remaining <= PracticeBlock.countdownTailSeconds {
            SoundEffectsPlayer.shared.playBeep()
        }
    }

    /// Schedules the count-in clicks and the audio resume. The runner is left in
    /// `.breakCountdown` until the count-in finishes, at which point it is drained
    /// to its terminal phase — the runner state machine itself is untouched.
    private func startBeatCountIn(_ plan: CountInPlan) {
        stopCountdown() // clears the 1s timer and any prior beat timers
        guard let block = runner.currentBlock else { finishBeatCountIn(); return }
        beatCountInRunning = true
        countInBeat = nil
        let sound = block.countInSound

        for click in plan.clicks {
            let timer = makeCommonModeTimer(after: max(click.offset, 0.0001)) { [weak self] in
                guard let self else { return }
                SoundEffectsPlayer.shared.playCountInTick(accent: click.isAccent, sound: sound)
                self.countInBeat = click.beatNumber
                self.audioStatus = "Count in: \(click.beatNumber)"
            }
            beatTimers.append(timer)
        }

        let finalize = makeCommonModeTimer(after: plan.totalDuration) { [weak self] in
            self?.finishBeatCountIn()
        }
        beatTimers.append(finalize)
    }

    private func cancelBeatCountIn() {
        beatTimers.forEach { $0.invalidate() }
        beatTimers.removeAll()
        beatCountInRunning = false
        countInBeat = nil
    }

    /// Count-in finished: drain the runner's remaining rest to its terminal phase
    /// (playing / manual wait) and start the next rep — mirroring the resolution
    /// the 1s countdown performs when it reaches zero.
    private func finishBeatCountIn() {
        cancelBeatCountIn()
        // Drain the rest without side effects; the final tick sets the post-rest phase.
        while runner.tickCountdown() {}
        audioStatus = phaseDescription

        switch runner.phase {
        case .playing:
            guard prepareCurrentBlockForPlayback() else { return }
            playCurrentSection()
        case .waitingForManualStart:
            if slideQueuedAutoStart {
                slideQueuedAutoStart = false
                runner.startFromManualWait()
                guard prepareCurrentBlockForPlayback() else { return }
                playCurrentSection()
            } else {
                audioPlayer.pause()
                stopPlayheadTimer()
            }
        case .idle, .breakCountdown, .complete:
            break
        }
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
        beginPlayback(from: block.section.startTime)
    }

    /// Plays the current section from `start` through its end, arming the playhead
    /// and auto-advance timers. Shared by normal rep playback and `rewind(by:)` so
    /// a rewind re-arms the exact same well-tested segment/seek/auto-stop path.
    private func beginPlayback(from start: TimeInterval) {
        guard let block = runner.currentBlock else { return }
        cancelPlaybackEnd()

        let endTime = block.section.endTime
        let clampedStart = min(max(start, block.section.startTime), endTime)
        let remaining = endTime - clampedStart
        guard remaining > 0.01 else {
            onSectionPlaybackFinished()
            return
        }

        currentSegmentEndTime = endTime
        isPaused = false

        audioPlayer.rate = playbackRate
        audioPlayer.playSegment(startTime: clampedStart, endTime: endTime)
        audioStatus = "Playing \(block.section.displayName) — Rep \(runner.currentRep)/\(block.reps)"
        startPlayheadTimer()

        // Schedule auto-advance when the section finishes playing. The engine
        // starts up to 0.5s early for the pre-roll fade-in, so match its actual
        // run time — otherwise the rest countdown kicks in while audio is still
        // playing the final half-second.
        let preRoll = min(clampedStart, AudioPlaybackEngine.preRollFadeSeconds)
        let realDelay = (remaining + preRoll) / Double(max(playbackRate, 0.01))
        if realDelay > 0 {
            playbackEndTimer = makeCommonModeTimer(after: realDelay) { [weak self] in
                self?.onSectionPlaybackFinished()
            }
        }
    }

    /// Jump to an absolute `time` inside the current section (e.g. tapping the
    /// global timeline within the active section). Clamps to the section range.
    /// Playing → re-arms playback from there; paused → seeks (picked up on resume);
    /// otherwise makes this the live section and starts from the tapped point.
    func jumpWithinCurrentSection(to time: TimeInterval) {
        guard let block = runner.currentBlock else { return }
        let clamped = min(max(time, block.section.startTime), block.section.endTime)

        if isPaused {
            audioPlayer.seek(to: clamped)
            currentPlaybackTime = clamped
            return
        }

        if case .playing = runner.phase {
            beginPlayback(from: clamped)
            return
        }

        // Idle / rest / manual-wait / complete: promote this section to live and
        // start from the tapped point.
        stopCountdown()
        slideQueuedAutoStart = false
        runner.restartBlock()
        guard prepareCurrentBlockForPlayback() else { return }
        beginPlayback(from: clamped)
        startSessionTimer()
        keepScreenAwake(true)
    }

    /// Rewind within the current section by `seconds`, clamped to the section
    /// start. Coach ergonomic: "they didn't hit it — run it back a beat." Works
    /// whether playing (re-arms playback) or paused (the seek is picked up on resume).
    func rewind(by seconds: TimeInterval = 5) {
        guard case .playing = runner.phase, let block = runner.currentBlock else { return }
        if isPaused {
            let target = max(currentPlaybackTime - seconds, block.section.startTime)
            audioPlayer.seek(to: target)
            currentPlaybackTime = target
            return
        }
        let target = max(audioPlayer.currentTime - seconds, block.section.startTime)
        beginPlayback(from: target)
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
