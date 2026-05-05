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
                            Button { controller.resetSession() } label: {
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Step progress
                    PPStepProgress(
                        steps: ["Trim section", "Arm cue", "Run repeats"],
                        activeIndex: stepIndex
                    )
                    .padding(.top, 8)

                    // Session progress bar
                    sessionProgressBar

                    // Hero header
                    heroSection(block: block)

                    // Countdown display (when applicable)
                    countdownDisplay

                    // Live cue card
                    cueStatusCard(block: block)

                    // Metrics row
                    metricsRow(block: block)

                    // Block queue
                    blockQueueSection

                    // Controls
                    controlsSection(block: block)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }

            // Global timeline strip
            if !controller.waveformSamples.isEmpty {
                GlobalTimelineStripView(
                    samples: controller.waveformSamples,
                    mixDuration: controller.session.mixDuration,
                    currentTime: controller.currentPlaybackTime,
                    sections: controller.session.sections,
                    activeSection: block.section,
                    onSeek: { controller.seek(to: $0) }
                )
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .background(PPColors.background)
            }

            // Bottom action bar
            bottomActionBar
        }
    }

    // MARK: - Step Index

    private var stepIndex: Int {
        switch controller.runner.phase {
        case .idle: return 1
        case .leadIn: return 1
        case .playing: return 2
        case .breakCountdown: return 2
        case .complete: return 2
        }
    }

    // MARK: - Session Progress Bar

    private var sessionProgressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("SESSION PROGRESS")
                    .font(PPFonts.caption(10))
                    .tracking(1.0)
                    .foregroundStyle(PPColors.textTertiary)

                Spacer()

                Text("\(Int(controller.runner.sessionProgress * 100))%")
                    .font(PPFonts.mono(12))
                    .foregroundStyle(PPColors.accentYellow)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PPColors.cardBorder)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [PPColors.accentYellow, PPColors.accentOrange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * controller.runner.sessionProgress)
                        .animation(.easeInOut(duration: 0.4), value: controller.runner.sessionProgress)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Block \(controller.runner.currentBlockIndex + 1)/\(controller.runner.totalBlocks)")
                    .font(PPFonts.mono(11))
                    .foregroundStyle(PPColors.textTertiary)

                Spacer()

                Text("Elapsed: \(Formatters.clock(controller.elapsedSessionTime))")
                    .font(PPFonts.mono(11))
                    .foregroundStyle(PPColors.textTertiary)
            }
        }
    }

    // MARK: - Hero Section

    private func heroSection(block: PracticeBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(phaseHeroTitle)
                    .font(PPFonts.hero(28))
                    .foregroundStyle(PPColors.textPrimary)

                PPPill(text: phaseStatusLabel, color: phaseStatusColor)
            }

            Text(block.title)
                .font(PPFonts.title())
                .foregroundStyle(PPColors.textSecondary)

            Text("\(block.section.name) • \(Formatters.clock(block.section.startTime)) → \(Formatters.clock(block.section.endTime))")
                .font(PPFonts.mono())
                .foregroundStyle(PPColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Countdown Display

    @ViewBuilder
    private var countdownDisplay: some View {
        switch controller.runner.phase {
        case .breakCountdown(let seconds):
            CountdownRingView(
                seconds: seconds,
                total: controller.runner.currentBlock?.restSeconds ?? 1,
                label: "BREAK",
                color: PPColors.accentOrange
            )
            .transition(.scale.combined(with: .opacity))

        case .leadIn(let seconds):
            CountdownRingView(
                seconds: seconds,
                total: controller.runner.currentBlock?.leadInSeconds ?? 1,
                label: "LEAD-IN",
                color: PPColors.accentYellow
            )
            .transition(.scale.combined(with: .opacity))

        default:
            EmptyView()
        }
    }

    // MARK: - Cue Status Card

    private func cueStatusCard(block: PracticeBlock) -> some View {
        VStack(spacing: 16) {
            // Phase icon with pulsing ring
            ZStack {
                if isActivePhase {
                    Circle()
                        .stroke(phaseStatusColor.opacity(0.3), lineWidth: 3)
                        .frame(width: 72, height: 72)
                        .scaleEffect(pulseScale)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                }

                Circle()
                    .fill(phaseStatusColor.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: phaseIcon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(phaseStatusColor)
            }
            .onAppear { pulseScale = 1.15 }

            Text(phaseLabel)
                .font(PPFonts.headline(18))
                .foregroundStyle(PPColors.textPrimary)

            // Rep counter dots
            HStack(spacing: 4) {
                ForEach(1...block.reps, id: \.self) { rep in
                    Circle()
                        .fill(rep <= controller.runner.currentRep ? PPColors.accentYellow : PPColors.cardBorder)
                        .frame(width: 10, height: 10)
                        .animation(.spring(response: 0.3), value: controller.runner.currentRep)
                }
            }

            Text("Rep \(max(controller.runner.currentRep, 1)) of \(block.reps)")
                .font(PPFonts.mono())
                .foregroundStyle(PPColors.textSecondary)

            // Audio status
            Text(controller.audioStatus)
                .font(PPFonts.mono(11))
                .foregroundStyle(PPColors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .ppCard(highlighted: isActivePhase)
    }

    // MARK: - Metrics

    private func metricsRow(block: PracticeBlock) -> some View {
        HStack(spacing: 12) {
            PPMetricCard(
                label: "Rest",
                value: "\(block.restSeconds)s",
                icon: "timer",
                accentColor: PPColors.accentOrange
            )

            PPMetricCard(
                label: "Lead-In",
                value: "\(block.leadInSeconds)s",
                icon: "metronome",
                accentColor: PPColors.accentYellow
            )

            PPMetricCard(
                label: "Mode",
                value: block.restartMode == .automatic ? "Auto" : "Man",
                icon: block.restartMode == .automatic ? "repeat" : "hand.tap",
                accentColor: PPColors.textSecondary
            )
        }
    }

    // MARK: - Block Queue

    private var blockQueueSection: some View {
        VStack(spacing: 12) {
            PPSectionHeader(title: "Block Queue", subtitle: "\(controller.runner.totalRepsCompleted)/\(controller.runner.totalReps) total reps")

            VStack(spacing: 2) {
                ForEach(Array(controller.session.blocks.enumerated()), id: \.element.id) { index, block in
                    BlockQueueRow(
                        block: block,
                        index: index,
                        isActive: index == controller.runner.currentBlockIndex,
                        isCompleted: index < controller.runner.currentBlockIndex,
                        currentRep: index == controller.runner.currentBlockIndex ? controller.runner.currentRep : 0
                    ) {
                        controller.jumpToBlock(index: index)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(PPColors.card))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Controls

    private func controlsSection(block: PracticeBlock) -> some View {
        VStack(spacing: 12) {
            PPSectionHeader(title: "Controls")

            VStack(spacing: 1) {
                PPDiagnosticRow(icon: "play.fill", label: "Play section") {
                    controller.playCurrentBlock()
                }

                Divider().background(PPColors.cardBorder)

                PPDiagnosticRow(icon: "pause.fill", label: "Pause playback") {
                    controller.pausePlayback()
                }

                Divider().background(PPColors.cardBorder)

                PPDiagnosticRow(icon: "timer", label: "Start break", value: "\(block.restSeconds)s") {
                    controller.beginBreak()
                }

                Divider().background(PPColors.cardBorder)

                PPDiagnosticRow(icon: "metronome", label: "Start lead-in", value: "\(block.leadInSeconds)s") {
                    controller.beginLeadIn()
                }

                Divider().background(PPColors.cardBorder)

                PPDiagnosticRow(icon: "backward.fill", label: "Previous block") {
                    controller.previousBlock()
                }

                Divider().background(PPColors.cardBorder)

                PPDiagnosticRow(icon: "forward.fill", label: "Skip to next block") {
                    controller.skipBlock()
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(PPColors.card))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [PPColors.background.opacity(0), PPColors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 30)

            HStack(spacing: 12) {
                // Main action button
                Button {
                    handleMainAction()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mainActionIcon)
                            .font(.system(size: 18, weight: .bold))
                        Text(mainActionLabel.uppercased())
                            .font(PPFonts.headline(15))
                            .tracking(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(mainActionColor)
                    .foregroundStyle(mainActionForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: controller.runner.phase)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(PPColors.background)
        }
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
        case .playing, .leadIn: return true
        default: return false
        }
    }

    private var phaseHeroTitle: String {
        switch controller.runner.phase {
        case .idle: return "READY TO GO"
        case .playing: return "NOW PLAYING"
        case .breakCountdown: return "BREAK TIME"
        case .leadIn: return "LEAD-IN"
        case .complete: return "SESSION DONE"
        }
    }

    private var phaseStatusLabel: String {
        switch controller.runner.phase {
        case .idle: return "Armed"
        case .playing: return "Live"
        case .breakCountdown: return "Rest"
        case .leadIn: return "Counting"
        case .complete: return "Done"
        }
    }

    private var phaseStatusColor: Color {
        switch controller.runner.phase {
        case .idle: return PPColors.accentYellow
        case .playing: return PPColors.success
        case .breakCountdown: return PPColors.accentOrange
        case .leadIn: return PPColors.accentYellow
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
            return "Break — \(secondsRemaining)s remaining"
        case .leadIn(let secondsRemaining):
            return "Lead-In — \(secondsRemaining)s"
        case .complete:
            return "Session Complete 🎉"
        }
    }

    private var phaseIcon: String {
        switch controller.runner.phase {
        case .idle: return "bolt.circle.fill"
        case .playing: return "play.circle.fill"
        case .breakCountdown: return "timer"
        case .leadIn: return "metronome.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }

    private var mainActionLabel: String {
        switch controller.runner.phase {
        case .idle: return "Start Playing"
        case .playing: return "Pause"
        case .breakCountdown: return "Skip Break"
        case .leadIn: return "Skip Lead-In"
        case .complete: return "Restart Session"
        }
    }

    private var mainActionIcon: String {
        switch controller.runner.phase {
        case .idle: return "play.fill"
        case .playing: return "pause.fill"
        case .breakCountdown: return "forward.fill"
        case .leadIn: return "forward.fill"
        case .complete: return "arrow.counterclockwise"
        }
    }

    private var mainActionColor: Color {
        switch controller.runner.phase {
        case .idle: return PPColors.accentYellow
        case .playing: return PPColors.card
        case .breakCountdown: return PPColors.accentOrange
        case .leadIn: return PPColors.accentYellow
        case .complete: return PPColors.success
        }
    }

    private var mainActionForeground: Color {
        switch controller.runner.phase {
        case .playing: return .white
        default: return .black
        }
    }

    // MARK: - Actions

    private func handleMainAction() {
        switch controller.runner.phase {
        case .idle:
            controller.playCurrentBlock()
        case .playing:
            controller.pausePlayback()
        case .breakCountdown:
            controller.playCurrentBlock()
        case .leadIn:
            controller.playCurrentBlock()
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
    let isCompleted: Bool
    let currentRep: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status indicator
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 32, height: 32)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(PPColors.success)
                    } else {
                        Text("\(index + 1)")
                            .font(PPFonts.mono(13))
                            .foregroundStyle(statusColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(block.title)
                        .font(PPFonts.headline(14))
                        .foregroundStyle(isActive ? PPColors.textPrimary : PPColors.textSecondary)

                    HStack(spacing: 8) {
                        Text(block.section.name)
                        Text("•")
                        Text("\(block.reps) reps")
                        if isActive && currentRep > 0 {
                            Text("•")
                            Text("Rep \(currentRep)")
                                .foregroundStyle(PPColors.accentYellow)
                        }
                    }
                    .font(PPFonts.mono(11))
                    .foregroundStyle(PPColors.textTertiary)
                }

                Spacer()

                Text(Formatters.clock(block.estimatedDuration))
                    .font(PPFonts.mono(12))
                    .foregroundStyle(PPColors.textTertiary)

                if isActive {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(PPColors.accentYellow)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isActive ? PPColors.cardHighlight : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        if isCompleted { return PPColors.success }
        if isActive { return PPColors.accentYellow }
        return PPColors.textTertiary
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
    let sections: [PracticeSection]
    let activeSection: PracticeSection?
    let onSeek: (TimeInterval) -> Void

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

                    // Section overlays
                    if mixDuration > 0 {
                        ForEach(sections) { section in
                            let startFrac = CGFloat(section.startTime / mixDuration)
                            let endFrac = CGFloat(section.endTime / mixDuration)
                            let sectionW = max((endFrac - startFrac) * totalWidth, 2)
                            let isActive = section.id == activeSection?.id

                            Rectangle()
                                .fill(section.type.accentColor.opacity(isActive ? 0.30 : 0.10))
                                .frame(width: sectionW, height: totalHeight)
                                .offset(x: startFrac * totalWidth)

                            if isActive {
                                Rectangle()
                                    .fill(section.type.accentColor.opacity(0.85))
                                    .frame(width: sectionW, height: 2)
                                    .offset(x: startFrac * totalWidth)
                                    .frame(maxHeight: .infinity, alignment: .top)
                            }
                        }
                    }

                    // Playhead
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
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard mixDuration > 0 else { return }
                            let clamped = max(0, min(value.location.x, totalWidth))
                            onSeek(Double(clamped / totalWidth) * mixDuration)
                        }
                )
            }
            .frame(height: 44)

            HStack {
                Text(Formatters.clock(currentTime))
                    .foregroundStyle(PPColors.accentYellow)
                Spacer()
                if let section = activeSection {
                    Text(section.name)
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
