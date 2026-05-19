import SwiftUI

struct PracticeBuilderView: View {
    @Binding var session: PrototypeSession
    let mixLibrary: MixLibraryStore
    let onResetRun: () -> Void

    @State private var isImportingMix = false
    @State private var isShowingLibrary = false
    @State private var importErrorMessage: String?
    @State private var waveformSamples: [Float] = []
    @State private var previewingSection: PracticeSection?
    @State private var previewEngine = AudioPlaybackEngine()
    @State private var previewPlayhead: TimeInterval = 0
    @State private var previewPollTimer: Timer?

    var body: some View {
        NavigationStack {
            ZStack {
                PPColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        heroHeader
                        trackCard
                        if session.mix != nil {
                            timelineOverview
                            sectionsList
                            blocksOverview
                            practiceTimeSummary
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }

                // Anchored CTA bar
                VStack {
                    Spacer()
                    ctaBar
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isImportingMix = true
                        } label: {
                            Label("Import Mix", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            isShowingLibrary = true
                        } label: {
                            Label("Load from Library", systemImage: "tray.full")
                        }
                        .disabled(mixLibrary.mixes.isEmpty)

                        if session.mix != nil && !session.sections.isEmpty {
                            Button {
                                saveCurrentToLibrary()
                            } label: {
                                Label("Save to Library", systemImage: "square.and.arrow.down.on.square")
                            }
                        }

                        Divider()

                        Button {
                            onResetRun()
                        } label: {
                            Label("Reset Run", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PPColors.textSecondary)
                    }
                }
            }
            .fileImporter(
                isPresented: $isImportingMix,
                allowedContentTypes: MixImportService.supportedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleMixImport(result)
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "Unknown import error")
            }
            .task(id: session.mix?.id) {
                await loadWaveform()
            }
            .sheet(isPresented: $isShowingLibrary) {
                MixLibraryView(library: mixLibrary) { savedMix in
                    loadFromLibrary(savedMix)
                }
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BUILD YOUR")
                .font(PPFonts.hero(36))
                .foregroundStyle(PPColors.textPrimary)
            Text("REPEAT MAP")
                .font(PPFonts.hero(36))
                .foregroundStyle(PPColors.accentYellow)

            Text("Trim the section, set the break, then run it")
                .font(PPFonts.body(14))
                .foregroundStyle(PPColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Track Card

    private var trackCard: some View {
        VStack(spacing: 0) {
            if let mix = session.mix {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(PPColors.accentYellow.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: "music.note")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(PPColors.accentYellow)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(mix.displayName)
                            .font(PPFonts.headline())
                            .foregroundStyle(PPColors.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 12) {
                            Label(Formatters.clock(mix.duration), systemImage: "clock")
                            Label(session.teamName, systemImage: "person.3")
                        }
                        .font(PPFonts.mono())
                        .foregroundStyle(PPColors.textSecondary)
                    }

                    Spacer()

                    Button {
                        isImportingMix = true
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PPColors.textTertiary)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(PPColors.accentYellow)

                    Text("Import your team mix to get started")
                        .font(PPFonts.body(15))
                        .foregroundStyle(PPColors.textSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button {
                            isImportingMix = true
                        } label: {
                            Label("Import Mix", systemImage: "square.and.arrow.down")
                                .font(PPFonts.headline(14))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(PPColors.accentYellow)
                                .foregroundStyle(.black)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        if !mixLibrary.mixes.isEmpty {
                            Button {
                                isShowingLibrary = true
                            } label: {
                                Label("Library", systemImage: "tray.full")
                                    .font(PPFonts.headline(14))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(PPColors.cardBorder)
                                    .foregroundStyle(PPColors.textPrimary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .ppCard()
    }

    // MARK: - Timeline Overview

    private var timelineOverview: some View {
        VStack(spacing: 8) {
            PPSectionHeader(title: "Track Timeline", subtitle: "All sections on the mix")

            SectionTimelineView(
                sections: session.sections,
                totalDuration: session.mixDuration
            )
        }
    }

    // MARK: - Sections List

    private var sectionsList: some View {
        VStack(spacing: 12) {
            PPSectionHeader(title: "Section Markers", subtitle: "\(session.sections.count) sections defined")

            ForEach(session.sections) { section in
                BuilderSectionCard(
                    section: section,
                    maxDuration: max(session.mixDuration, 1),
                    waveformSamples: waveformSamples,
                    isPreviewing: previewingSection?.id == section.id,
                    playheadTime: previewingSection?.id == section.id ? previewPlayhead : nil,
                    onChange: { updated in
                        session.upsertSection(updated)
                    },
                    onDelete: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            session.removeSection(id: section.id)
                        }
                    },
                    onAddBlock: {
                        withAnimation(.spring(response: 0.35)) {
                            session.addBlock(for: section)
                        }
                    },
                    onPreview: {
                        previewSection(section)
                    },
                    onSeek: { time in seekPreview(section: section, to: time) },
                    onDuplicate: {
                        duplicateSection(section)
                    }
                )
            }

            Button {
                withAnimation(.spring(response: 0.35)) {
                    session.addSection(PracticeSection.blank(totalDuration: max(session.mixDuration, 32)))
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Section")
                }
                .font(PPFonts.headline(14))
                .foregroundStyle(PPColors.accentYellow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(PPColors.accentYellow.opacity(0.3), lineWidth: 1, antialiased: true)
                )
            }
            .buttonStyle(.plain)
            .disabled(session.mix == nil && session.mixDuration == 0)
        }
    }

    // MARK: - Blocks Overview

    private var blocksOverview: some View {
        VStack(spacing: 12) {
            PPSectionHeader(title: "Practice Blocks", subtitle: "\(session.blocks.count) blocks • \(Formatters.clock(session.totalEstimatedDuration)) total")

            ForEach($session.blocks) { $block in
                BuilderBlockCard(block: $block, onDelete: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        session.blocks.removeAll { $0.id == block.id }
                    }
                }, onDuplicate: {
                    duplicateBlock(block)
                })
            }
        }
    }

    // MARK: - Practice Time Summary

    private var practiceTimeSummary: some View {
        VStack(spacing: 12) {
            PPSectionHeader(title: "Time Breakdown")

            VStack(spacing: 1) {
                ForEach(session.blocks) { block in
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(block.section.type.accentColor)
                            .frame(width: 4, height: 20)

                        Text(block.title)
                            .font(PPFonts.mono(13))
                            .foregroundStyle(PPColors.textSecondary)

                        Spacer()

                        // Breakdown
                        HStack(spacing: 6) {
                            timeBreakdownPill("play", value: Formatters.clock(block.section.duration * Double(block.reps)))
                            timeBreakdownPill("rest", value: Formatters.clock(Double(max(block.reps - 1, 0) * block.restSeconds)))
                            timeBreakdownPill("lead", value: Formatters.clock(Double(block.reps * block.leadInSeconds)))
                        }

                        Text(Formatters.clock(block.estimatedDuration))
                            .font(PPFonts.mono(13))
                            .foregroundStyle(PPColors.textPrimary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }

                Divider().background(PPColors.cardBorder)

                HStack {
                    Text("TOTAL")
                        .font(PPFonts.caption(11))
                        .tracking(1.0)
                        .foregroundStyle(PPColors.textTertiary)

                    Spacer()

                    Text(Formatters.clock(session.totalEstimatedDuration))
                        .font(PPFonts.monoLarge(20))
                        .foregroundStyle(PPColors.accentYellow)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(PPColors.card))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func timeBreakdownPill(_ label: String, value: String) -> some View {
        Text("\(label) \(value)")
            .font(PPFonts.caption(9))
            .foregroundStyle(PPColors.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    // MARK: - CTA Bar

    private var ctaBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [PPColors.background.opacity(0), PPColors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 30)

            VStack(spacing: 8) {
                PPPrimaryButton("Start Practicing", icon: "play.fill") {
                    onResetRun()
                }

                Text("Saves loop, then enters live mode")
                    .font(PPFonts.caption(11))
                    .foregroundStyle(PPColors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(PPColors.background)
        }
        .opacity(session.blocks.isEmpty ? 0.4 : 1.0)
        .allowsHitTesting(!session.blocks.isEmpty)
    }

    // MARK: - Actions

    private func saveCurrentToLibrary() {
        guard let mix = session.mix else { return }
        mixLibrary.save(mix, sections: session.sections)
    }

    private func loadFromLibrary(_ savedMix: SavedMix) {
        session.mix = savedMix.mix
        session.sections = savedMix.sections
        session.blocks = []
    }

    private func previewSection(_ section: PracticeSection) {
        seekPreview(section: section, to: section.startTime)
    }

    private func seekPreview(section: PracticeSection, to time: TimeInterval) {
        guard let mix = session.mix else { return }
        do {
            try previewEngine.load(url: mix.localURL)
            let endTime = section.endTime
            previewEngine.playSegment(startTime: time, endTime: endTime)
            previewPlayhead = time
            previewingSection = section
            startPreviewPollTimer()
            let remaining = max(endTime - time, 0.1)
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                if self.previewingSection?.id == section.id {
                    self.previewingSection = nil
                    self.stopPreviewPollTimer()
                }
            }
        } catch {}
    }

    private func startPreviewPollTimer() {
        stopPreviewPollTimer()
        previewPollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in self.previewPlayhead = self.previewEngine.currentTime }
        }
    }

    private func stopPreviewPollTimer() {
        previewPollTimer?.invalidate()
        previewPollTimer = nil
    }

    private func duplicateSection(_ section: PracticeSection) {
        var newSection = section
        newSection = PracticeSection(
            id: UUID(),
            name: "\(section.name) Copy",
            type: section.type,
            startTime: section.startTime,
            endTime: section.endTime
        )
        withAnimation(.spring(response: 0.35)) {
            session.addSection(newSection)
        }
    }

    private func duplicateBlock(_ block: PracticeBlock) {
        let newBlock = PracticeBlock(
            id: UUID(),
            title: "\(block.title) Copy",
            section: block.section,
            reps: block.reps,
            restSeconds: block.restSeconds,
            leadInSeconds: block.leadInSeconds,
            restartMode: block.restartMode
        )
        withAnimation(.spring(response: 0.35)) {
            session.blocks.append(newBlock)
        }
    }

    private func loadWaveform() async {
        guard let path = session.mix?.localPath else {
            waveformSamples = []
            return
        }
        let url = URL(fileURLWithPath: path)
        do {
            waveformSamples = try await WaveformExtractor.extractSamples(from: url)
        } catch {
            waveformSamples = []
        }
    }

    private func handleMixImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let selectedURL = urls.first else {
            if case .failure(let error) = result {
                importErrorMessage = error.localizedDescription
            }
            return
        }

        Task {
            do {
                let importedMix = try await MixImportService().importMix(from: selectedURL)
                await MainActor.run {
                    session.attachMix(importedMix)
                    if session.sections.isEmpty {
                        session.addSection(PracticeSection.blank(totalDuration: importedMix.duration))
                    }
                }
            } catch {
                await MainActor.run {
                    importErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Section Timeline View

private struct SectionTimelineView: View {
    let sections: [PracticeSection]
    let totalDuration: TimeInterval

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width

                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(PPColors.card)

                    // Section markers
                    ForEach(sections) { section in
                        let startFrac = totalDuration > 0 ? section.startTime / totalDuration : 0
                        let endFrac = totalDuration > 0 ? section.endTime / totalDuration : 1
                        let x = CGFloat(startFrac) * w
                        let barWidth = max(CGFloat(endFrac - startFrac) * w, 2)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(section.type.accentColor.opacity(0.6))
                            .frame(width: barWidth, height: 24)
                            .offset(x: x)
                    }
                }
            }
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Time labels
            HStack {
                Text("0:00")
                Spacer()
                Text(Formatters.clock(totalDuration / 2))
                Spacer()
                Text(Formatters.clock(totalDuration))
            }
            .font(PPFonts.mono(10))
            .foregroundStyle(PPColors.textTertiary)
        }
        .ppCard()
    }
}

// MARK: - Section Editor Card

private struct BuilderSectionCard: View {
    let section: PracticeSection
    let maxDuration: TimeInterval
    let waveformSamples: [Float]
    let isPreviewing: Bool
    var playheadTime: TimeInterval?
    let onChange: (PracticeSection) -> Void
    let onDelete: () -> Void
    let onAddBlock: () -> Void
    let onPreview: () -> Void
    var onSeek: ((TimeInterval) -> Void)?
    let onDuplicate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack {
                PPPill(text: section.type.label, color: section.type.accentColor, textColor: .black)

                if isPreviewing {
                    PPPill(text: "Playing", color: PPColors.success, textColor: .black)
                }

                Spacer()

                // Preview button
                Button { onPreview() } label: {
                    Image(systemName: isPreviewing ? "speaker.wave.2.fill" : "play.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isPreviewing ? PPColors.success : PPColors.textTertiary)
                }
                .buttonStyle(.plain)

                Menu {
                    Button { onAddBlock() } label: {
                        Label("Add Block", systemImage: "plus.square.on.square")
                    }
                    Button { onDuplicate() } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete Section", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PPColors.textTertiary)
                        .frame(width: 32, height: 32)
                }
            }

            // Name field
            TextField(
                "Section Name",
                text: Binding(
                    get: { section.name },
                    set: { newValue in
                        var updated = section
                        updated.name = newValue
                        onChange(updated)
                    }
                )
            )
            .font(PPFonts.headline())
            .foregroundStyle(PPColors.textPrimary)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))

            // Type picker
            Picker(
                "Type",
                selection: Binding(
                    get: { section.type },
                    set: { newValue in
                        var updated = section
                        updated.type = newValue
                        onChange(updated)
                    }
                )
            ) {
                ForEach(PracticeSection.SectionType.allCases, id: \.self) { type in
                    Label(type.label, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.menu)
            .tint(PPColors.accentYellow)

            // Waveform or sliders
            if waveformSamples.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    timeSlider(label: "Start", value: section.startTime) { newValue in
                        var updated = section
                        updated.startTime = min(newValue, updated.endTime)
                        onChange(updated)
                    }
                    timeSlider(label: "End", value: section.endTime) { newValue in
                        var updated = section
                        updated.endTime = max(newValue, updated.startTime)
                        onChange(updated)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    WaveformTrimmerView(
                        samples: waveformSamples,
                        duration: maxDuration,
                        startTime: Binding(
                            get: { section.startTime },
                            set: { newValue in
                                var updated = section
                                updated.startTime = newValue
                                onChange(updated)
                            }
                        ),
                        endTime: Binding(
                            get: { section.endTime },
                            set: { newValue in
                                var updated = section
                                updated.endTime = newValue
                                onChange(updated)
                            }
                        ),
                        playheadTime: playheadTime,
                        onSeek: onSeek
                    )

                    TrimTimeLabelsView(startTime: section.startTime, endTime: section.endTime)
                }
            }

            // Duration badge
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                Text("Duration: \(Formatters.clock(section.duration))")
                    .font(PPFonts.mono(12))
            }
            .foregroundStyle(PPColors.textTertiary)
        }
        .ppCard()
    }

    private func timeSlider(label: String, value: TimeInterval, onChange: @escaping (TimeInterval) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(PPFonts.mono())
                    .foregroundStyle(PPColors.textSecondary)
                Spacer()
                Text(Formatters.clock(value))
                    .font(PPFonts.mono())
                    .foregroundStyle(PPColors.accentYellow)
            }
            Slider(value: Binding(get: { value }, set: onChange), in: 0...maxDuration)
                .tint(PPColors.accentYellow)
        }
    }
}

// MARK: - Block Card

private struct BuilderBlockCard: View {
    @Binding var block: PracticeBlock
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Block Title", text: $block.title)
                    .font(PPFonts.headline())
                    .foregroundStyle(PPColors.textPrimary)

                Spacer()

                Menu {
                    Button { onDuplicate() } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PPColors.textTertiary)
                        .frame(width: 32, height: 32)
                }
            }

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(block.section.type.accentColor)
                    .frame(width: 4, height: 16)

                Text(block.section.name)
                    .font(PPFonts.mono())
                    .foregroundStyle(PPColors.textTertiary)

                Text("•")
                    .foregroundStyle(PPColors.textTertiary)

                Text(Formatters.clock(block.section.startTime) + " → " + Formatters.clock(block.section.endTime))
                    .font(PPFonts.mono())
                    .foregroundStyle(PPColors.textTertiary)
            }

            // Steppers with custom styling
            HStack(spacing: 12) {
                compactStepper(label: "Reps", value: $block.reps, range: 1...12)
                compactStepper(label: "Rest", value: $block.restSeconds, range: 0...180, step: 5, suffix: "s")
                compactStepper(label: "Lead-in", value: $block.leadInSeconds, range: 0...32, suffix: "s")
            }

            Picker("Restart", selection: $block.restartMode) {
                ForEach(PracticeBlock.RestartMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 12))
                Text("Est: \(Formatters.clock(block.estimatedDuration))")
                    .font(PPFonts.mono())
            }
            .foregroundStyle(PPColors.textTertiary)
        }
        .ppCard()
    }

    private func compactStepper(label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, suffix: String = "") -> some View {
        VStack(spacing: 6) {
            Text(label.uppercased())
                .font(PPFonts.caption(10))
                .tracking(0.8)
                .foregroundStyle(PPColors.textTertiary)

            HStack(spacing: 4) {
                Button {
                    let newVal = value.wrappedValue - step
                    if newVal >= range.lowerBound { value.wrappedValue = newVal }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(PPColors.textSecondary)
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)\(suffix)")
                    .font(PPFonts.mono(14))
                    .foregroundStyle(PPColors.textPrimary)
                    .frame(minWidth: 32)

                Button {
                    let newVal = value.wrappedValue + step
                    if newVal <= range.upperBound { value.wrappedValue = newVal }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(PPColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Section Type Extensions

extension PracticeSection.SectionType {
    var label: String {
        switch self {
        case .warmup: return "Warmup"
        case .jumps: return "Jumps"
        case .standingTumbling: return "Standing Tumbling"
        case .runningTumbling: return "Running Tumbling"
        case .pyramid: return "Pyramid"
        case .dance: return "Dance"
        case .fullOut: return "Full Out"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .warmup: return "flame"
        case .jumps: return "figure.jumprope"
        case .standingTumbling: return "figure.gymnastics"
        case .runningTumbling: return "figure.run"
        case .pyramid: return "triangle"
        case .dance: return "figure.dance"
        case .fullOut: return "bolt.fill"
        case .custom: return "star"
        }
    }

    var accentColor: Color {
        switch self {
        case .warmup: return Color(red: 0.4, green: 0.85, blue: 0.95)
        case .jumps: return PPColors.accentYellow
        case .standingTumbling: return PPColors.accentOrange
        case .runningTumbling: return PPColors.accentOrange
        case .pyramid: return Color(red: 0.75, green: 0.5, blue: 1.0)
        case .dance: return Color(red: 1.0, green: 0.5, blue: 0.7)
        case .fullOut: return PPColors.destructive
        case .custom: return PPColors.textSecondary
        }
    }
}
