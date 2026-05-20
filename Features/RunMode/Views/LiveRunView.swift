import SwiftUI

struct LiveRunView: View {
    @Bindable var controller: LiveSessionController

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                PPColors.background.ignoresSafeArea()

                if let block = controller.runner.currentBlock {
                    activeSessionView(block: block)
                } else {
                    emptyStateView
                }
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

    // MARK: - Active Session

    private func activeSessionView(block: PracticeBlock) -> some View {
        VStack(spacing: 16) {
            // Countdown ring (only during break)
            countdownDisplay
                .padding(.top, 4)

            // Primary practice status cue card — houses the integrated play/pause control!
            cueStatusCard(block: block)

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
                    onSelectBlock: { controller.selectBlock(at: $0) }
                )
            }

            // Bottom action bar — speed control only.
            bottomActionBar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Countdown Display

    @ViewBuilder
    private var countdownDisplay: some View {
        switch controller.runner.phase {
        case .breakCountdown(let seconds):
            let isTail = seconds <= PracticeBlock.countdownTailSeconds
            CountdownRingView(
                seconds: seconds,
                total: controller.runner.currentBlock?.restSeconds ?? 1,
                label: isTail ? "GET READY" : "REST",
                color: isTail ? PPColors.accentYellow : PPColors.accentOrange
            )
            .transition(.scale.combined(with: .opacity))

        default:
            EmptyView()
        }
    }

    // MARK: - Cue Status Card

    private func cueStatusCard(block: PracticeBlock) -> some View {
        let accent = PPColors.blockColor(at: controller.runner.currentBlockIndex)
        let attempted = controller.repsAttempted[block.id] ?? 0
        let isComplete = controller.runner.phase == .complete
        let borderColor: Color = isActivePhase
            ? phaseStatusColor.opacity(0.6)
            : (controller.runner.phase == .idle ? phaseStatusColor.opacity(0.5) : PPColors.cardBorder)

        return Button(action: handleMainAction) {
            HStack(spacing: 16) {
                // Visual play indicator — the WHOLE card is the button; this is just the icon.
                ZStack {
                    if isActivePhase {
                        Circle()
                            .stroke(phaseStatusColor.opacity(0.45), lineWidth: 4)
                            .frame(width: 72, height: 72)
                            .scaleEffect(pulseScale)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulseScale)
                    }
                    Circle()
                        .fill(phaseStatusColor)
                        .frame(width: 60, height: 60)
                        .shadow(color: phaseStatusColor.opacity(0.4), radius: 8, x: 0, y: 2)
                    Image(systemName: mainActionIcon)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(mainActionForeground)
                        .offset(x: mainActionIcon == "play.fill" ? 2 : 0)
                }

                // Center column: title + phase label + pips
                VStack(alignment: .leading, spacing: 4) {
                    if !isComplete {
                        Text(block.title)
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
                                Circle()
                                    .fill(rep <= attempted ? accent : PPColors.cardBorder)
                                    .frame(width: 9, height: 9)
                                    .animation(.spring(response: 0.3), value: attempted)
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
                        Label(block.restartMode == .automatic ? "Auto" : "Manual",
                              systemImage: block.restartMode == .automatic ? "repeat" : "hand.tap")
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
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: controller.runner.phase)
        .onAppear { pulseScale = 1.15 }
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
                    BlockQueueRow(
                        block: block,
                        index: index,
                        isActive: index == controller.runner.currentBlockIndex && controller.runner.phase != .complete,
                        attempted: controller.repsAttempted[block.id] ?? 0,
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
        HStack {
            Spacer()
            speedPill
            Spacer()
        }
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
        let rounded = (rate * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 0.001 {
            return String(format: "%.0f×", rounded)
        }
        let trimmed = String(format: "%.2f", rounded)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        return "\(trimmed)×"
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
        switch controller.runner.phase {
        case .playing: return true
        default: return false
        }
    }

    private var phaseStatusColor: Color {
        switch controller.runner.phase {
        case .idle: return PPColors.accentYellow
        case .playing: return PPColors.success
        case .breakCountdown(let s):
            return s <= PracticeBlock.countdownTailSeconds ? PPColors.accentYellow : PPColors.accentOrange
        case .complete: return PPColors.success
        }
    }

    private var phaseLabel: String {
        switch controller.runner.phase {
        case .idle:
            return "Tap Play to Begin"
        case .playing:
            return "Playing"
        case .breakCountdown(let secondsRemaining):
            if secondsRemaining <= PracticeBlock.countdownTailSeconds {
                return "Get ready — \(secondsRemaining)"
            }
            return "Rest — \(secondsRemaining)s remaining"
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
        case .complete: return "checkmark.circle.fill"
        }
    }

    private var mainActionLabel: String {
        if controller.isPaused { return "Resume" }
        switch controller.runner.phase {
        case .idle: return "Start Playing"
        case .playing: return "Pause"
        case .breakCountdown: return "Skip Rest"
        case .complete: return "Restart Session"
        }
    }

    private var mainActionIcon: String {
        if controller.isPaused { return "play.fill" }
        switch controller.runner.phase {
        case .idle: return "play.fill"
        case .playing: return "pause.fill"
        case .breakCountdown: return "forward.fill"
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
        case .idle:
            controller.playCurrentBlock()
        case .playing:
            controller.pausePlayback()
        case .breakCountdown:
            controller.skipBreak()
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

                Text(block.title)
                    .font(PPFonts.headline(14))
                    .foregroundStyle(isActive ? PPColors.textPrimary : PPColors.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if block.reps > 0 {
                    HStack(spacing: 4) {
                        ForEach(1...block.reps, id: \.self) { rep in
                            Circle()
                                .fill(rep <= attempted ? accent : PPColors.cardBorder)
                                .frame(width: 8, height: 8)
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
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Countdown Ring

private struct CountdownRingView: View {
    let seconds: Int
    let total: Int
    let label: String
    let color: Color

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(seconds) / Double(total)
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(PPColors.cardBorder, lineWidth: 8)
                    .frame(width: 120, height: 120)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                // Center text
                VStack(spacing: 2) {
                    Text("\(seconds)")
                        .font(PPFonts.hero(40))
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: seconds)

                    Text(label)
                        .font(PPFonts.caption(10))
                        .tracking(1.5)
                        .foregroundStyle(PPColors.textTertiary)
                }
            }
        }
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

    @State private var hoverBlockIndex: Int?

    private var activeBlock: PracticeBlock? {
        blocks.indices.contains(activeBlockIndex) ? blocks[activeBlockIndex] : nil
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
                            if let index = resolveBlock(at: value.location.x, totalWidth: totalWidth) {
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
                    Text(block.section.name)
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
