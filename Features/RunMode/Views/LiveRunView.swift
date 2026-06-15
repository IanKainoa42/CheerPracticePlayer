import SwiftUI

struct LiveRunView: View {
    @Bindable var controller: LiveSessionController

    @State private var pulseScale: CGFloat = 1.0
    /// Bumped each time the user taps the cue card while it is actively playing.
    /// Acts as a trigger for warning haptics — pause requires a hold gesture.
    @State private var holdGuardNudgeCount: Int = 0
    @State private var isResetConfirmPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                PPColors.background.ignoresSafeArea()

                if let block = controller.runner.currentBlock {
                    activeSessionView(block: block)
                } else {
                    emptyStateView
                }

                editNoticeBanner
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if controller.runner.currentBlock != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { controller.restartBlock() } label: {
                                Label("Restart This Block", systemImage: "arrow.uturn.backward")
                            }
                            Divider()
                            Button(role: .destructive) { controller.resetSession() } label: {
                                Label("Reset Session", systemImage: "arrow.counterclockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(PPColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Edit Notice Banner

    /// Non-interfering banner that surfaces a transient notice (e.g. "Edit saved —
    /// applies at next rep") when the user mutates the in-flight block from the
    /// Build tab. Floats over the top of the Live view, fades in/out, auto-dismisses,
    /// and tap-to-dismiss. Never intercepts gestures meant for the play controls.
    @ViewBuilder
    private var editNoticeBanner: some View {
        VStack {
            if let message = controller.pendingEditNotice {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(message)
                        .font(PPFonts.body(14))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(PPColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(PPColors.card)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                )
                .overlay(
                    Capsule().strokeBorder(PPColors.accentYellow.opacity(0.6), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { controller.dismissEditNotice() }
            }
            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: controller.pendingEditNotice)
        .allowsHitTesting(controller.pendingEditNotice != nil)
    }

    // MARK: - Active Session

    private func activeSessionView(block: PracticeBlock) -> some View {
        VStack(spacing: 16) {
            // Always-present countdown ring — its footprint never changes, so the
            // cue card, block queue, and timeline below never reflow when a break
            // starts/ends. Counts down rest during a break, and the section's
            // remaining time while playing.
            countdownDisplay
                .padding(.top, 4)

            // Primary practice status cue card — houses the integrated play/pause control!
            cueStatusCard(block: block)

            // Slide-to-skip-rest slot — ALWAYS occupies the same vertical space
            // so the cue card and block queue below never reflow when entering
            // or leaving rest. The slide control is only interactive during rest
            // with remaining > tail; otherwise the slot renders empty.
            slideSkipSlot

            // Block queue takes the remaining flexible vertical space
            blockQueueSection
                .frame(maxHeight: .infinity, alignment: .top)

            // Global timeline strip
            if !controller.waveformSamples.isEmpty {
                GlobalTimelineStripView(
                    samples: controller.waveformSamples,
                    mixDuration: controller.session.mixDuration,
                    currentTime: controller.currentPlaybackTime,
                    blocks: controller.session.blocks,
                    activeBlockIndex: controller.runner.currentBlockIndex,
                    onSelectBlock: { controller.selectBlock(at: $0) },
                    onSeekWithinActive: { controller.jumpWithinCurrentSection(to: $0) }
                )
            }

            // Bottom action bar — speed control only.
            bottomActionBar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Countdown Display

    /// The always-present circular gauge. Its footprint is constant across every
    /// phase, so showing/hiding a countdown never reflows the views below it.
    /// - Rest break: counts the rest seconds down (orange → yellow in the tail).
    /// - Playing: counts the current section's remaining time down (green).
    /// - Idle / waiting / complete: a dim ring so the slot stays anchored.
    private var countdownDisplay: some View {
        let info = ringInfo
        return CountdownRingView(
            number: info.number,
            progress: info.progress,
            label: info.label,
            color: info.color,
            isDim: info.isDim
        )
    }

    /// Per-phase configuration for the countdown ring.
    private var ringInfo: (number: Int?, progress: Double, label: String, color: Color, isDim: Bool) {
        let section = controller.runner.currentBlock?.section
        let sectionDuration = max((section.map { $0.endTime - $0.startTime }) ?? 0, 0.001)

        if controller.isPaused {
            let remaining = section.map { max(0, $0.endTime - controller.currentPlaybackTime) } ?? 0
            return (Int(remaining.rounded(.up)), remaining / sectionDuration, "PAUSED", PPColors.accentYellow, true)
        }

        switch controller.runner.phase {
        case .playing:
            let remaining = section.map { max(0, $0.endTime - controller.currentPlaybackTime) } ?? 0
            return (Int(remaining.rounded(.up)), remaining / sectionDuration, "PLAYING", PPColors.success, false)

        case .breakCountdown(let seconds):
            let total = max(controller.runner.currentBlock?.restSeconds ?? 1, 1)
            let isTail = seconds <= PracticeBlock.countdownTailSeconds
            return (seconds,
                    Double(seconds) / Double(total),
                    isTail ? "GET READY" : "REST",
                    isTail ? PPColors.accentYellow : PPColors.accentOrange,
                    false)

        case .waitingForManualStart:
            return (Int(sectionDuration.rounded(.up)), 1, "TAP TO START", PPColors.accentYellow, true)

        case .complete:
            return (nil, 1, "DONE", PPColors.success, true)

        case .idle:
            return (Int(sectionDuration.rounded(.up)), 1, "READY", PPColors.textSecondary, true)
        }
    }

    // MARK: - Slide-to-skip slot

    /// Fixed-height container for the slide-to-skip-rest control. Reserved on
    /// EVERY phase so the cue card + block queue below stay anchored — the
    /// "no reflow" promise made by the always-present countdown ring would
    /// otherwise be broken by this widget appearing/disappearing.
    private var slideSkipSlot: some View {
        ZStack {
            if case .breakCountdown(let remaining) = controller.runner.phase,
               remaining > PracticeBlock.countdownTailSeconds,
               !controller.isPaused {
                SlideToSkipRest {
                    controller.skipBreakToCountdownTail()
                }
                .transition(.opacity)
            } else if controller.runner.phase == .playing {
                // Playing (or paused mid-section): live transport — rewind a beat
                // or skip the whole current section without waiting it out.
                transportControls
                    .transition(.opacity)
            }
        }
        // Match SlideToSkipRest's thumbSize (44) so the slot is exactly its height.
        .frame(height: 44)
        .animation(.easeInOut(duration: 0.2), value: controller.runner.phase)
        .animation(.easeInOut(duration: 0.2), value: controller.isPaused)
    }

    /// Live transport controls shown under the cue card during playback. Rewind
    /// runs the section back 5s (clamped to its start); Skip Section jumps to the
    /// next section immediately.
    private var transportControls: some View {
        HStack(spacing: 10) {
            transportButton(icon: "gobackward.5", label: "REWIND 5s", tint: PPColors.textPrimary) {
                controller.rewind(by: 5)
            }
            transportButton(icon: "forward.end.fill", label: "SKIP SECTION", tint: PPColors.accentOrange) {
                controller.skipBlock()
            }
        }
    }

    private func transportButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(PPFonts.caption(10))
                    .tracking(1.2)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Capsule().fill(PPColors.card))
            .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cue Status Card

    @ViewBuilder
    private func cueStatusCard(block: PracticeBlock) -> some View {
        let cardBody = cueCardContent(block: block)
        if isActivePhase {
            // While actively playing, the card is "locked" — a stray tap will not
            // stop the mix. A long-press is required to pause.
            cardBody
                .onTapGesture { holdGuardNudgeCount &+= 1 }
                .onLongPressGesture(minimumDuration: 0.6) {
                    controller.pausePlayback()
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: controller.runner.phase)
                .sensoryFeedback(.warning, trigger: holdGuardNudgeCount)
                .onAppear { pulseScale = 1.15 }
        } else {
            Button(action: handleMainAction) { cardBody }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: controller.runner.phase)
                .onAppear { pulseScale = 1.15 }
        }
    }

    private func cueCardContent(block: PracticeBlock) -> some View {
        let accent = PPColors.blockColor(at: controller.runner.currentBlockIndex)
        let attempted = controller.repsAttempted[block.id] ?? 0
        let isComplete = controller.runner.phase == .complete
        // The rep currently being PLAYED (not paused, not resting). Drives the
        // blinking pip in the cue card so the coach sees which rep is live.
        let playingRep: Int? = {
            guard !controller.isPaused, case .playing = controller.runner.phase else { return nil }
            return controller.runner.currentRep
        }()
        let borderColor: Color = isActivePhase
            ? phaseStatusColor.opacity(0.6)
            : (controller.runner.phase == .idle ? phaseStatusColor.opacity(0.5) : PPColors.cardBorder)

        return HStack(spacing: 16) {
                // Visual play indicator — the WHOLE card is the button; this is just the icon.
                // Frame is locked so the pulse animation cannot reflow the HStack.
                ZStack {
                    if isActivePhase {
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: 3)
                            .frame(width: 70, height: 70)
                            .scaleEffect(pulseScale)
                            .opacity(2.0 - Double(pulseScale))
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulseScale)
                            .allowsHitTesting(false)
                    }
                    Circle()
                        .fill(phaseStatusColor)
                        .frame(width: 60, height: 60)
                        .shadow(color: phaseStatusColor.opacity(0.4), radius: 8, x: 0, y: 2)
                    Image(systemName: mainActionIcon)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(mainActionForeground)
                        .frame(width: 30, height: 30)
                }
                .frame(width: 84, height: 84)

                // Center column: title + phase label + pips
                VStack(alignment: .leading, spacing: 4) {
                    if !isComplete {
                        Text(block.section.displayName)
                            .font(PPFonts.headline(15))
                            .foregroundStyle(PPColors.textPrimary)
                            .lineLimit(1)
                    }
                    Text(phaseLabel)
                        .font(PPFonts.headline(18))
                        .foregroundStyle(PPColors.textPrimary)
                    if !isComplete {
                        HStack(spacing: 4) {
                            ForEach(1...block.reps, id: \.self) { rep in
                                PipDot(
                                    isCredited: rep <= attempted,
                                    isPlayingNow: rep == playingRep,
                                    accent: accent,
                                    size: 9
                                )
                            }
                            Text("\(attempted)/\(block.reps)")
                                .font(PPFonts.mono(11))
                                .foregroundStyle(PPColors.textSecondary)
                                .padding(.leading, 4)
                        }
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer()

                // Right column: rest seconds + mode (compact)
                if !isComplete {
                    VStack(alignment: .trailing, spacing: 4) {
                        Label("\(block.restSeconds)s", systemImage: "timer")
                            .font(PPFonts.mono(12))
                            .foregroundStyle(PPColors.accentOrange)
                        Label(block.restartMode.label, systemImage: block.restartMode.iconName)
                            .font(PPFonts.mono(11))
                            .foregroundStyle(PPColors.textTertiary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isActivePhase ? PPColors.cardHighlight : PPColors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(borderColor, lineWidth: isActivePhase ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Block Queue

    private var blockQueueSection: some View {
        let totalAttempted = controller.session.blocks.reduce(0) { $0 + (controller.repsAttempted[$1.id] ?? 0) }
        return VStack(spacing: 12) {
            PPSectionHeader(
                title: "Block Queue",
                subtitle: "\(totalAttempted)/\(controller.runner.totalReps) reps attempted • tap to jump"
            )

            VStack(spacing: 2) {
                ForEach(Array(controller.session.blocks.enumerated()), id: \.element.id) { index, block in
                    let isPlayingThisBlock = !controller.isPaused
                        && index == controller.runner.currentBlockIndex
                        && controller.runner.phase == .playing
                    BlockQueueRow(
                        block: block,
                        index: index,
                        isActive: index == controller.runner.currentBlockIndex && controller.runner.phase != .complete,
                        attempted: controller.repsAttempted[block.id] ?? 0,
                        playingRep: isPlayingThisBlock ? controller.runner.currentRep : nil,
                        accent: PPColors.blockColor(at: index)
                    ) {
                        controller.selectBlock(at: index)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(PPColors.card))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Spacer()
            speedPill
            Spacer()
            endSessionButton
        }
        .alert(
            "End this session?",
            isPresented: $isResetConfirmPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("End Session", role: .destructive) { controller.resetSession() }
        } message: {
            Text("Audio stops and the runner resets to the first block. Reps attempted this session are cleared.")
        }
    }

    /// Visible, always-on Reset button. The toolbar ⋯ menu was easy to miss
    /// during active playback; coaches need a clear way to wipe the runner
    /// without hunting through a menu. Confirmation alert prevents accidental
    /// taps from nuking a live practice.
    private var endSessionButton: some View {
        Button {
            isResetConfirmPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("END")
                    .font(PPFonts.caption(10))
                    .tracking(1.4)
            }
            .foregroundStyle(PPColors.accentOrange)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Capsule().fill(PPColors.card))
            .overlay(Capsule().strokeBorder(PPColors.accentOrange.opacity(0.6), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var speedPill: some View {
        let isOffOne = abs(controller.playbackRate - 1.0) > 0.001
        return Button {
            controller.cyclePlaybackRate()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOffOne ? PPColors.accentYellow : PPColors.textTertiary)
                Text(formattedRate(controller.playbackRate))
                    .font(PPFonts.mono(15))
                    .foregroundStyle(PPColors.textPrimary)
                Text("SPEED")
                    .font(PPFonts.caption(9))
                    .tracking(1.4)
                    .foregroundStyle(PPColors.textTertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(
                Capsule().fill(PPColors.card)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isOffOne ? PPColors.accentYellow.opacity(0.8) : PPColors.cardBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: controller.playbackRate)
    }

    private func formattedRate(_ rate: Float) -> String {
        let percent = Int((rate * 100).rounded())
        return "\(percent)%"
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(PPColors.textTertiary)

            Text("NO BLOCKS")
                .font(PPFonts.hero(24))
                .foregroundStyle(PPColors.textPrimary)

            Text("Create at least one practice block in the Build tab to start a live session.")
                .font(PPFonts.body(15))
                .foregroundStyle(PPColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Computed Properties

    private var isActivePhase: Bool {
        if controller.isPaused { return false }
        switch controller.runner.phase {
        case .playing: return true
        default: return false
        }
    }

    private var phaseStatusColor: Color {
        if controller.isPaused { return PPColors.accentYellow }
        switch controller.runner.phase {
        case .idle: return PPColors.accentYellow
        case .playing: return PPColors.success
        case .breakCountdown(let s):
            return s <= PracticeBlock.countdownTailSeconds ? PPColors.accentYellow : PPColors.accentOrange
        case .waitingForManualStart: return PPColors.accentYellow
        case .complete: return PPColors.success
        }
    }

    private var phaseLabel: String {
        if controller.isPaused { return "Paused" }
        switch controller.runner.phase {
        case .idle:
            return "Tap Play to Begin"
        case .playing:
            return "Playing — hold to pause"
        case .breakCountdown(let secondsRemaining):
            if secondsRemaining <= PracticeBlock.countdownTailSeconds {
                return "Get ready — \(secondsRemaining)"
            }
            return "Rest — \(secondsRemaining)s remaining"
        case .waitingForManualStart:
            return "Tap to start next rep"
        case .complete:
            return "Session Complete 🎉"
        }
    }

    private var phaseIcon: String {
        switch controller.runner.phase {
        case .idle: return "bolt.circle.fill"
        case .playing: return "play.circle.fill"
        case .breakCountdown(let s):
            return s <= PracticeBlock.countdownTailSeconds ? "metronome.fill" : "timer"
        case .waitingForManualStart: return "hand.tap.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }

    private var mainActionLabel: String {
        if controller.isPaused { return "Resume" }
        switch controller.runner.phase {
        case .idle: return "Start Playing"
        case .playing: return "Pause"
        case .breakCountdown: return "Resting — slide below to skip"
        case .waitingForManualStart: return "Start Next Rep"
        case .complete: return "Restart Session"
        }
    }

    private var mainActionIcon: String {
        if controller.isPaused { return "play.fill" }
        switch controller.runner.phase {
        case .idle: return "play.fill"
        case .playing: return "pause.fill"
        case .breakCountdown(let s):
            // Skip is now via the slide control; show a timer/metronome icon
            // so the giant circle doesn't read as a tap-to-skip affordance.
            return s <= PracticeBlock.countdownTailSeconds ? "metronome.fill" : "timer"
        case .waitingForManualStart: return "hand.tap.fill"
        case .complete: return "arrow.counterclockwise"
        }
    }

    private var mainActionColor: Color {
        if controller.isPaused { return PPColors.accentYellow }
        switch controller.runner.phase {
        case .idle: return PPColors.accentYellow
        case .playing: return PPColors.card
        case .breakCountdown(let s):
            return s <= PracticeBlock.countdownTailSeconds ? PPColors.accentYellow : PPColors.accentOrange
        case .waitingForManualStart: return PPColors.accentYellow
        case .complete: return PPColors.success
        }
    }

    private var mainActionForeground: Color {
        if controller.isPaused { return .black }
        switch controller.runner.phase {
        case .playing: return .white
        default: return .black
        }
    }

    // MARK: - Actions

    private func handleMainAction() {
        if controller.isPaused {
            controller.resumePlayback()
            return
        }
        switch controller.runner.phase {
        case .idle, .waitingForManualStart:
            controller.playCurrentBlock()
        case .playing:
            controller.pausePlayback()
        case .breakCountdown:
            // Skip-rest is now driven by the SlideToSkipRest control below the
            // cue card — a stray tap on the card must not cut the rest short.
            holdGuardNudgeCount &+= 1
        case .complete:
            controller.resetSession()
        }
    }
}

// MARK: - Block Queue Row

private struct BlockQueueRow: View {
    let block: PracticeBlock
    let index: Int
    let isActive: Bool
    let attempted: Int
    /// The rep currently being played in THIS block, or nil if this row is not
    /// the active playing block (or the player is paused/resting). Drives the
    /// blinking pip so the queue echoes the cue card's live state.
    let playingRep: Int?
    let accent: Color
    let onTap: () -> Void

    private var isFullyAttempted: Bool { attempted >= block.reps && block.reps > 0 }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 32, height: 32)

                    if isFullyAttempted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                    } else {
                        Text("\(index + 1)")
                            .font(PPFonts.mono(13))
                            .foregroundStyle(accent)
                    }
                }

                Text(block.section.displayName)
                    .font(PPFonts.headline(14))
                    .foregroundStyle(isActive ? PPColors.textPrimary : PPColors.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if block.reps > 0 {
                    HStack(spacing: 4) {
                        ForEach(1...block.reps, id: \.self) { rep in
                            PipDot(
                                isCredited: rep <= attempted,
                                isPlayingNow: rep == playingRep,
                                accent: accent,
                                size: 8
                            )
                        }
                    }
                }

                if isActive {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isActive ? PPColors.cardHighlight : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Countdown Ring

private struct CountdownRingView: View {
    /// Center number, or nil to hide it (e.g. when complete).
    let number: Int?
    let progress: Double
    let label: String
    let color: Color
    /// Dim the whole ring without changing its footprint (idle / waiting / paused / done).
    let isDim: Bool

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(PPColors.cardBorder, lineWidth: 8)
                .frame(width: 120, height: 120)

            // Progress ring
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            // Center text
            VStack(spacing: 2) {
                if let number {
                    Text("\(number)")
                        .font(PPFonts.hero(40))
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: number)
                }

                Text(label)
                    .font(PPFonts.caption(10))
                    .tracking(1.5)
                    .foregroundStyle(PPColors.textTertiary)
            }
        }
        .opacity(isDim ? 0.4 : 1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Global Timeline Strip

private struct GlobalTimelineStripView: View {
    let samples: [Float]
    let mixDuration: TimeInterval
    let currentTime: TimeInterval
    let blocks: [PracticeBlock]
    let activeBlockIndex: Int
    let onSelectBlock: (Int) -> Void
    /// Called when the tap lands inside the active section — passes the absolute
    /// time so the live run can seek to that exact point instead of restarting.
    let onSeekWithinActive: (TimeInterval) -> Void

    @State private var hoverBlockIndex: Int?

    private var activeBlock: PracticeBlock? {
        blocks.indices.contains(activeBlockIndex) ? blocks[activeBlockIndex] : nil
    }

    /// Absolute mix time for an x position in the strip.
    private func time(at x: CGFloat, totalWidth: CGFloat) -> TimeInterval {
        guard totalWidth > 0, mixDuration > 0 else { return 0 }
        let frac = max(0, min(Double(x / totalWidth), 1))
        return frac * mixDuration
    }

    /// Resolve a tap/drag x-position to a block index — either the block whose section
    /// contains that time, or the nearest block by section midpoint.
    private func resolveBlock(at x: CGFloat, totalWidth: CGFloat) -> Int? {
        guard !blocks.isEmpty, mixDuration > 0, totalWidth > 0 else { return nil }
        let frac = max(0, min(Double(x / totalWidth), 1))
        let t = frac * mixDuration
        if let containing = blocks.firstIndex(where: { t >= $0.section.startTime && t < $0.section.endTime }) {
            return containing
        }
        // Snap to nearest by section midpoint.
        var bestIndex = 0
        var bestDistance = Double.infinity
        for (i, block) in blocks.enumerated() {
            let mid = (block.section.startTime + block.section.endTime) / 2
            let d = abs(mid - t)
            if d < bestDistance { bestDistance = d; bestIndex = i }
        }
        return bestIndex
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let totalHeight = geo.size.height

                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.06))

                    // Waveform bars
                    Canvas { context, size in
                        let count = samples.count
                        guard count > 0 else { return }
                        let gap: CGFloat = 1
                        let barW = max((size.width - CGFloat(count - 1) * gap) / CGFloat(count), 1)
                        for (index, amp) in samples.enumerated() {
                            let xPos = CGFloat(index) * (barW + gap)
                            let barH = max(CGFloat(amp) * size.height * 0.75, 1)
                            let yPos = (size.height - barH) / 2
                            context.fill(
                                Path(roundedRect: CGRect(x: xPos, y: yPos, width: barW, height: barH),
                                     cornerRadius: 0.5),
                                with: .color(.white.opacity(0.18))
                            )
                        }
                    }

                    // Block overlays — each section that's "throwing" gets its block-accent fill
                    // and an Nx multiplier showing reps.
                    if mixDuration > 0 {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                            let startFrac = CGFloat(block.section.startTime / mixDuration)
                            let endFrac = CGFloat(block.section.endTime / mixDuration)
                            let sectionW = max((endFrac - startFrac) * totalWidth, 2)
                            let isActive = index == activeBlockIndex
                            let accent = PPColors.blockColor(at: index)

                            Rectangle()
                                .fill(accent.opacity(isActive ? 0.35 : 0.18))
                                .frame(width: sectionW, height: totalHeight)
                                .offset(x: startFrac * totalWidth)

                            if isActive {
                                Rectangle()
                                    .fill(accent.opacity(0.95))
                                    .frame(width: sectionW, height: 2)
                                    .offset(x: startFrac * totalWidth)
                                    .frame(maxHeight: .infinity, alignment: .top)
                            }

                            // Rep multiplier badge (e.g., "3×"). Only when there's room to read it.
                            if block.reps > 1 && sectionW >= 24 {
                                Text("\(block.reps)×")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(accent.opacity(isActive ? 1.0 : 0.85))
                                    )
                                    .position(
                                        x: startFrac * totalWidth + min(sectionW / 2, 20),
                                        y: 9
                                    )
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    // Playhead (always tracks audio time, not the user's finger)
                    if mixDuration > 0 {
                        let playFrac = CGFloat(max(0, min(currentTime / mixDuration, 1)))
                        ZStack(alignment: .top) {
                            Rectangle()
                                .fill(Color.white.opacity(0.88))
                                .frame(width: 2, height: totalHeight)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 6, height: 6)
                                .offset(y: 1)
                        }
                        .shadow(color: .white.opacity(0.5), radius: 3)
                        .offset(x: playFrac * totalWidth - 1)
                        .allowsHitTesting(false)
                    }

                    // Hover highlight while finger is down — shows which block will be selected.
                    if let hover = hoverBlockIndex, blocks.indices.contains(hover) {
                        let hoverBlock = blocks[hover]
                        let startFrac = CGFloat(hoverBlock.section.startTime / mixDuration)
                        let endFrac = CGFloat(hoverBlock.section.endTime / mixDuration)
                        let w = max((endFrac - startFrac) * totalWidth, 2)
                        Rectangle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 2)
                            .frame(width: w, height: totalHeight - 2)
                            .offset(x: startFrac * totalWidth, y: 1)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            hoverBlockIndex = resolveBlock(at: value.location.x, totalWidth: totalWidth)
                        }
                        .onEnded { value in
                            let t = time(at: value.location.x, totalWidth: totalWidth)
                            // Tap inside the section you're already in → seek to that
                            // exact point. Tap elsewhere → jump to that block's start.
                            if let active = activeBlock,
                               t >= active.section.startTime, t < active.section.endTime {
                                onSeekWithinActive(t)
                            } else if let index = resolveBlock(at: value.location.x, totalWidth: totalWidth) {
                                onSelectBlock(index)
                            }
                            hoverBlockIndex = nil
                        }
                )
            }
            .frame(height: 44)

            HStack {
                Text(Formatters.clock(currentTime))
                    .foregroundStyle(PPColors.accentYellow)
                Spacer()
                if let block = activeBlock {
                    Text(block.section.displayName)
                        .foregroundStyle(PPColors.textTertiary)
                    Spacer()
                }
                Text(Formatters.clock(mixDuration))
                    .foregroundStyle(PPColors.textTertiary)
            }
            .font(PPFonts.mono(10))
        }
    }
}

// MARK: - Pip Dot

/// A single rep indicator. Credited reps fill solid in the block accent.
/// The currently-playing rep blinks in the accent so the coach can see at a
/// glance which rep is live. Idle reps are a flat cardBorder dot.
private struct PipDot: View {
    let isCredited: Bool
    let isPlayingNow: Bool
    let accent: Color
    var size: CGFloat = 9

    var body: some View {
        if isPlayingNow {
            // TimelineView.animation redraws every frame so the sine-driven
            // opacity is reliable across phase transitions — no @State race.
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                // ~0.9Hz sinusoid → 0.35–1.0 opacity range. Calm, not strobey.
                let envelope = (sin(t * .pi * 1.8) * 0.5) + 0.5
                Circle()
                    .fill(accent)
                    .frame(width: size, height: size)
                    .opacity(0.35 + envelope * 0.65)
            }
            .frame(width: size, height: size)
        } else {
            Circle()
                .fill(isCredited ? accent : PPColors.cardBorder)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Slide To Skip Rest

/// A horizontal "slide-to-confirm" control. The thumb starts on the left; the
/// user drags it past 85% of the track width to fire the action. A stray tap
/// must NOT trigger the action — that's the whole point during a rest interval.
private struct SlideToSkipRest: View {
    let onConfirm: () -> Void

    @State private var dragX: CGFloat = 0
    @State private var confirmed = false

    private let thumbSize: CGFloat = 44
    private let triggerFraction: CGFloat = 0.85

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let maxDrag = max(trackWidth - thumbSize, 0)
            let progress = maxDrag > 0 ? min(dragX / maxDrag, 1) : 0

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: thumbSize / 2)
                    .fill(PPColors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: thumbSize / 2)
                            .strokeBorder(PPColors.accentOrange.opacity(0.5), lineWidth: 1)
                    )

                // Filled track behind the thumb
                RoundedRectangle(cornerRadius: thumbSize / 2)
                    .fill(PPColors.accentOrange.opacity(0.25 + 0.45 * progress))
                    .frame(width: dragX + thumbSize)

                // Label
                HStack {
                    Spacer()
                    Text(confirmed ? "Skipping to warning…" : "Slide to skip rest →")
                        .font(PPFonts.headline(13))
                        .tracking(0.5)
                        .foregroundStyle(PPColors.textPrimary.opacity(0.85 - 0.4 * progress))
                    Spacer()
                }
                .allowsHitTesting(false)

                // Thumb
                ZStack {
                    Circle()
                        .fill(PPColors.accentOrange)
                        .shadow(color: PPColors.accentOrange.opacity(0.4), radius: 6, x: 0, y: 2)
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.black)
                }
                .frame(width: thumbSize, height: thumbSize)
                .offset(x: dragX)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !confirmed else { return }
                            dragX = max(0, min(value.translation.width, maxDrag))
                        }
                        .onEnded { _ in
                            guard !confirmed else { return }
                            if progress >= triggerFraction {
                                confirmed = true
                                withAnimation(.spring(response: 0.25)) {
                                    dragX = maxDrag
                                }
                                onConfirm()
                            } else {
                                withAnimation(.spring(response: 0.3)) {
                                    dragX = 0
                                }
                            }
                        }
                )
            }
        }
        .frame(height: thumbSize)
        .padding(.horizontal, 4)
        .sensoryFeedback(.success, trigger: confirmed)
    }
}
