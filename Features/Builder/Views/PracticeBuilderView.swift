import SwiftUI

struct PracticeBuilderView: View {
    @Binding var session: PrototypeSession
    let mixLibrary: MixLibraryStore
    let audioEngine: AudioPlaybackEngine
    @Binding var requestImport: Bool
    /// Called when the system file picker dismisses WITHOUT a successful import
    /// (user tapped Cancel or the importer failed). Lets the parent restore
    /// the originating tab — e.g. tap IMPORT MIX from Library → Cancel → back to Library
    /// instead of being stranded on Build (QA L2).
    var onImportCancelled: (() -> Void)? = nil

    @State private var isImportingMix = false
    @State private var didImportSucceed = false
    @State private var importErrorMessage: String?
    @State private var waveformSamples: [Float] = []
    @State private var previewingSection: PracticeSection?
    @State private var previewPlayhead: TimeInterval = 0
    @State private var previewPollTimer: Timer?
    @State private var previewEndTask: DispatchWorkItem?
    @State private var isPreviewPaused: Bool = false
    @State private var hasFirstSectionSaved: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                PPColors.background.ignoresSafeArea()

                if session.mix == nil {
                    emptyImportState
                } else if !hasFirstSectionSaved {
                    firstSectionMarkerView
                } else {
                    step3ProgramView
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
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
            .onAppear {
                // When a mix arrives pre-populated (e.g. loaded from Library tab),
                // skip the "Mark First Section" focus view and go straight to Program.
                if session.mix != nil && !session.sections.isEmpty {
                    hasFirstSectionSaved = true
                }
                if requestImport {
                    requestImport = false
                    isImportingMix = true
                }
            }
            .onChange(of: requestImport) { _, newValue in
                if newValue {
                    requestImport = false
                    didImportSucceed = false
                    isImportingMix = true
                }
            }
            .onChange(of: isImportingMix) { wasPresenting, isPresenting in
                // Picker dismissed without a successful import → tell the parent
                // so it can restore the originating tab (Library, if that's where
                // the user kicked off the import from).
                if wasPresenting && !isPresenting && !didImportSucceed {
                    onImportCancelled?()
                }
            }
            .onChange(of: session.sections) { _, _ in
                if let mixID = session.mix?.id {
                    mixLibrary.updateSections(for: mixID, sections: session.sections)
                }
            }
            .onChange(of: session.blocks) { _, _ in
                // Persist per-mix block programming (reps, restSeconds, restartMode).
                // Without this, switching to another mix and returning would silently
                // reset rest length and rep counts because loadFromLibrary rebuilds
                // blocks from sections.
                if let mixID = session.mix?.id {
                    mixLibrary.updateBlocks(for: mixID, blocks: session.blocks)
                }
            }
            .onDisappear {
                stopPreview()
            }
        }
    }




    // MARK: - Empty Import State

    private var emptyImportState: some View {
        VStack {
            Spacer()
            Button {
                isImportingMix = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18, weight: .bold))
                    Text("IMPORT MIX")
                        .font(PPFonts.headline(16))
                        .tracking(1.2)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(Capsule().fill(PPColors.accentYellow))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 2: First Section Marker

    private var firstSectionMarkerView: some View {
        let draftSection = session.sections.first
        let canSave = draftSection.map { $0.duration > 0 } ?? false

        return ZStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        Text("STEP 2 OF 3")
                            .font(PPFonts.caption(11))
                            .tracking(1.4)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(PPColors.accentYellow))

                        Text("MARK A SECTION\nOF THE MUSIC")
                            .font(PPFonts.hero(30))
                            .foregroundStyle(PPColors.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Drag the handles to set the in and out points of the phrase you want to repeat.")
                            .font(PPFonts.body(14))
                            .foregroundStyle(PPColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        Text(session.mix?.displayName.uppercased() ?? "")
                            .font(PPFonts.caption(10))
                            .tracking(1.0)
                            .foregroundStyle(PPColors.textTertiary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)

                        if let section = draftSection {
                            WaveformTrimmerView(
                                samples: waveformSamples,
                                duration: max(session.mixDuration, 1),
                                startTime: Binding(
                                    get: { section.startTime },
                                    set: { newValue in
                                        var updated = section
                                        updated.startTime = newValue
                                        session.upsertSection(updated)
                                        recalibratePreview(for: updated)
                                    }
                                ),
                                endTime: Binding(
                                    get: { section.endTime },
                                    set: { newValue in
                                        var updated = section
                                        updated.endTime = newValue
                                        session.upsertSection(updated)
                                        recalibratePreview(for: updated)
                                    }
                                ),
                                playheadTime: previewingSection?.id == section.id ? previewPlayhead : nil,
                                onSeek: { time in seekPreview(section: section, to: time) }
                            )

                            TrimTimeLabelsView(
                                startTime: section.startTime,
                                endTime: section.endTime,
                                mixDuration: session.mixDuration
                            )

                            if canSave {
                                previewControl(for: section)
                                    .padding(.top, 12)
                            }
                        }
                    }

                    Text("Don't worry about getting every section now — you can add as many as you want after this.")
                        .font(PPFonts.body(13))
                        .foregroundStyle(PPColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 140)
            }

            VStack {
                Spacer()
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [PPColors.background.opacity(0), PPColors.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)

                    VStack {
                        PPPrimaryButton("Save Section", icon: "checkmark") {
                            stopPreview()
                            ensureBlocksForAllSections()
                            withAnimation(.spring(response: 0.35)) {
                                hasFirstSectionSaved = true
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(PPColors.background)
                }
                .opacity(canSave ? 1.0 : 0.4)
                .allowsHitTesting(canSave)
            }
        }
    }

    private func previewControl(for section: PracticeSection) -> some View {
        let isThisActive = previewingSection?.id == section.id
        let isPlaying = isThisActive && !isPreviewPaused
        let icon = isPlaying ? "pause.fill" : "play.fill"
        let label = isThisActive ? (isPlaying ? "PAUSE" : "RESUME") : "PREVIEW SECTION"

        return Button {
            togglePreview(section)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [PPColors.accentYellow, PPColors.accentOrange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: PPColors.accentOrange.opacity(0.35), radius: 14, x: 0, y: 6)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.black)
                        .offset(x: isPlaying ? 0 : 2)
                }

                Text(label)
                    .font(PPFonts.caption(12))
                    .tracking(1.4)
                    .foregroundStyle(PPColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Program View

    private var step3ProgramView: some View {
        ScrollView {
            VStack(spacing: 28) {
                step3Hero
                programCardsList
                addSectionButton
                if !session.blocks.isEmpty {
                    totalTimeSummary
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .onAppear { ensureBlocksForAllSections() }
    }

    private var step3Hero: some View {
        VStack(spacing: 14) {
            Text("STEP 3 OF 3")
                .font(PPFonts.caption(11))
                .tracking(1.4)
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(PPColors.accentYellow))

            Text("PROGRAM YOUR\nPRACTICE")
                .font(PPFonts.hero(30))
                .foregroundStyle(PPColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Dial in reps and rest for each section. Add more sections any time.")
                .font(PPFonts.body(14))
                .foregroundStyle(PPColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Program Cards List

    private var programCardsList: some View {
        VStack(spacing: 16) {
            ForEach(Array(session.sections.enumerated()), id: \.element.id) { index, section in
                if let block = session.blocks.first(where: { $0.section.id == section.id }) {
                    ProgramSectionCard(
                        index: index,
                        section: section,
                        block: block,
                        maxDuration: max(session.mixDuration, 1),
                        waveformSamples: waveformSamples,
                        isPreviewing: previewingSection?.id == section.id,
                        isPreviewPaused: previewingSection?.id == section.id && isPreviewPaused,
                        playheadTime: previewingSection?.id == section.id ? previewPlayhead : nil,
                        onSectionChange: { updated in
                            session.upsertSection(updated)
                            recalibratePreview(for: updated)
                        },
                        onBlockChange: { updated in
                            if let i = session.blocks.firstIndex(where: { $0.id == updated.id }) {
                                session.blocks[i] = updated
                            }
                        },
                        onDelete: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if previewingSection?.id == section.id { stopPreview() }
                                session.removeSection(id: section.id)
                            }
                        },
                        onDuplicate: { duplicateSection(section) },
                        onPreview: { togglePreview(section) },
                        onSeek: { time in seekPreview(section: section, to: time) }
                    )
                }
            }
        }
    }

    private var addSectionButton: some View {
        Button {
            addSectionWithBlock()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("ADD ANOTHER SECTION")
                    .font(PPFonts.caption(12))
                    .tracking(1.2)
            }
            .foregroundStyle(PPColors.accentYellow)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(PPColors.accentYellow.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
        .disabled(session.mix == nil)
    }

    private var totalTimeSummary: some View {
        VStack(spacing: 6) {
            Text("TOTAL PRACTICE TIME")
                .font(PPFonts.caption(11))
                .tracking(1.4)
                .foregroundStyle(PPColors.textTertiary)
            Text(Formatters.clock(session.totalEstimatedDuration))
                .font(PPFonts.monoLarge(28))
                .foregroundStyle(PPColors.accentYellow)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func ensureBlocksForAllSections() {
        for section in session.sections where !session.blocks.contains(where: { $0.section.id == section.id }) {
            session.addBlock(for: section)
        }
    }

    private func addSectionWithBlock() {
        let newSection = PracticeSection.blank(totalDuration: max(session.mixDuration, 32))
        withAnimation(.spring(response: 0.35)) {
            session.addSection(newSection)
            if let added = session.sections.first(where: { $0.id == newSection.id }) {
                session.addBlock(for: added)
            }
        }
    }

    private func previewSection(_ section: PracticeSection) {
        seekPreview(section: section, to: section.startTime)
    }

    private func togglePreview(_ section: PracticeSection) {
        guard previewingSection?.id == section.id else {
            previewSection(section)
            return
        }
        if isPreviewPaused {
            audioEngine.rate = 1.0
            let remaining = max(section.endTime - audioEngine.currentTime, 0.1)
            audioEngine.resumeUntil(remainingDuration: remaining)
            isPreviewPaused = false
            startPreviewPollTimer()
            scheduleEndTask(after: remaining, section: section)
        } else {
            audioEngine.pause()
            isPreviewPaused = true
            stopPreviewPollTimer()
            previewEndTask?.cancel()
            previewEndTask = nil
        }
    }

    private func stopPreview() {
        if previewingSection != nil {
            audioEngine.pause()
        }
        previewEndTask?.cancel()
        previewEndTask = nil
        previewingSection = nil
        isPreviewPaused = false
        stopPreviewPollTimer()
    }

    private func seekPreview(section: PracticeSection, to time: TimeInterval) {
        guard let mix = session.mix else { return }
        let upperBound = max(section.endTime - 0.1, section.startTime)
        let clamped = min(max(time, section.startTime), upperBound)
        do {
            try audioEngine.load(url: mix.localURL)
            audioEngine.rate = 1.0
            audioEngine.playSegment(startTime: clamped, endTime: section.endTime)
            previewPlayhead = clamped
            previewingSection = section
            isPreviewPaused = false
            startPreviewPollTimer()
            scheduleEndTask(after: max(section.endTime - clamped, 0.1), section: section)
        } catch {}
    }

    private func recalibratePreview(for section: PracticeSection) {
        guard previewingSection?.id == section.id, !isPreviewPaused else { return }
        let current = audioEngine.currentTime
        if current >= section.endTime - 0.05 {
            stopPreview()
            return
        }
        var playheadTarget = current
        if current < section.startTime {
            playheadTarget = section.startTime
            audioEngine.seek(to: playheadTarget)
            previewPlayhead = playheadTarget
        }
        let remaining = max(section.endTime - playheadTarget, 0.1)
        audioEngine.rescheduleStop(remainingDuration: remaining)
        scheduleEndTask(after: remaining, section: section)
    }

    private func scheduleEndTask(after delay: TimeInterval, section: PracticeSection) {
        previewEndTask?.cancel()
        let task = DispatchWorkItem {
            guard self.previewingSection?.id == section.id else { return }
            self.previewingSection = nil
            self.isPreviewPaused = false
            self.stopPreviewPollTimer()
        }
        previewEndTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func startPreviewPollTimer() {
        stopPreviewPollTimer()
        previewPollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in self.previewPlayhead = self.audioEngine.currentTime }
        }
    }

    private func stopPreviewPollTimer() {
        previewPollTimer?.invalidate()
        previewPollTimer = nil
    }

    private func duplicateSection(_ section: PracticeSection) {
        let newSection = PracticeSection(
            id: UUID(),
            name: "\(section.displayName) Copy",
            type: section.type,
            startTime: section.startTime,
            endTime: section.endTime
        )
        // Carry the source block's programming (reps / rest / restartMode)
        // into the duplicate. Without this, duplicating a 7-rep / 35s-rest /
        // manual block silently resets it to defaults (QA M4).
        let sourceBlock = session.blocks.first(where: { $0.section.id == section.id })
        withAnimation(.spring(response: 0.35)) {
            session.addSection(newSection)
            guard let added = session.sections.first(where: { $0.id == newSection.id }) else { return }
            if let src = sourceBlock {
                session.blocks.append(
                    PracticeBlock(
                        id: UUID(),
                        title: added.name,
                        section: added.clamped(to: session.mixDuration),
                        reps: src.reps,
                        restSeconds: src.restSeconds,
                        restartMode: src.restartMode
                    )
                )
            } else {
                session.addBlock(for: added)
            }
        }
    }

    private func loadWaveform() async {
        guard let url = session.mix?.localURL else {
            waveformSamples = []
            return
        }
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
                    didImportSucceed = true
                    session.attachMix(importedMix)
                    session.sections = []
                    session.blocks = []
                    session.addSection(PracticeSection.blank(totalDuration: importedMix.duration))
                    hasFirstSectionSaved = false
                    mixLibrary.save(importedMix, sections: session.sections)
                }
            } catch {
                await MainActor.run {
                    importErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Program Section Card (Step 3)

private struct ProgramSectionCard: View {
    let index: Int
    let section: PracticeSection
    let block: PracticeBlock
    let maxDuration: TimeInterval
    let waveformSamples: [Float]
    let isPreviewing: Bool
    let isPreviewPaused: Bool
    var playheadTime: TimeInterval?
    let onSectionChange: (PracticeSection) -> Void
    let onBlockChange: (PracticeBlock) -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onPreview: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var isRestartHelpPresented = false
    @State private var isDeleteConfirmPresented = false

    private var numberLabel: String {
        String(format: "%02d", index + 1)
    }

    private var isActivelyPlaying: Bool {
        isPreviewing && !isPreviewPaused
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            waveform
            TrimTimeLabelsView(
                startTime: section.startTime,
                endTime: section.endTime,
                mixDuration: maxDuration
            )
            previewControl
            stepperTrio
            restartPicker
            estimatedDuration
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(PPColors.card))
        // Using `.alert` (not `.confirmationDialog`) so iPad shows a centered
        // modal with an explicit Cancel button. On iPad, confirmationDialog renders
        // as a popover that dismisses on tap-off with no labeled Cancel — coaches
        // were unsure whether tap-off saved or canceled the destructive action.
        .alert(
            "Delete \"\(section.displayName)\"?",
            isPresented: $isDeleteConfirmPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Section", role: .destructive) { onDelete() }
        } message: {
            Text("Its reps, rest length, and time range will be removed. This can't be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(numberLabel)
                .font(PPFonts.monoLarge(20))
                .foregroundStyle(PPColors.accentYellow)

            TextField(
                "Section name",
                text: Binding(
                    get: { section.name },
                    set: { newValue in
                        var updated = section
                        updated.name = newValue
                        onSectionChange(updated)
                    }
                )
            )
            .font(PPFonts.headline(17))
            .foregroundStyle(PPColors.textPrimary)

            Menu {
                Picker(
                    "Type",
                    selection: Binding(
                        get: { section.type },
                        set: { newValue in
                            var updated = section
                            updated.type = newValue
                            onSectionChange(updated)
                        }
                    )
                ) {
                    ForEach(PracticeSection.SectionType.allCases, id: \.self) { type in
                        Label(type.label, systemImage: type.icon).tag(type)
                    }
                }
                Divider()
                Button { onDuplicate() } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    isDeleteConfirmPresented = true
                } label: {
                    Label("Delete Section", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PPColors.textTertiary)
                    .frame(width: 32, height: 32)
            }
        }
    }

    private var waveform: some View {
        // Always show the waveform trimmer. Renders cleanly with empty samples
        // (background + handles only) while audio is decoding — never flash the
        // legacy Start/End sliders, which were deprecated UI.
        WaveformTrimmerView(
            samples: waveformSamples,
            duration: maxDuration,
            startTime: Binding(
                get: { section.startTime },
                set: { newValue in
                    var updated = section
                    updated.startTime = newValue
                    onSectionChange(updated)
                }
            ),
            endTime: Binding(
                get: { section.endTime },
                set: { newValue in
                    var updated = section
                    updated.endTime = newValue
                    onSectionChange(updated)
                }
            ),
            playheadTime: playheadTime,
            onSeek: onSeek
        )
    }

    private var previewControl: some View {
        let icon = isActivelyPlaying ? "pause.fill" : "play.fill"
        let label = isPreviewing
            ? (isActivelyPlaying ? "PAUSE" : "RESUME")
            : "PREVIEW SECTION"

        return Button(action: onPreview) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [PPColors.accentYellow, PPColors.accentOrange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: PPColors.accentOrange.opacity(0.35), radius: 12, x: 0, y: 5)

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.black)
                        .offset(x: isActivelyPlaying ? 0 : 1.5)
                }

                Text(label)
                    .font(PPFonts.caption(12))
                    .tracking(1.4)
                    .foregroundStyle(PPColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var stepperTrio: some View {
        HStack(spacing: 10) {
            substantialStepper(label: "REPS", value: block.reps, range: 1...12, step: 1, suffix: "") { newVal in
                var u = block
                u.reps = newVal
                onBlockChange(u)
            }
            substantialStepper(label: "REST", value: block.restSeconds, range: 0...180, step: 5, suffix: "s") { newVal in
                var u = block
                u.restSeconds = newVal
                onBlockChange(u)
            }
        }
    }

    private var restartPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Restart Mode", systemImage: "repeat")
                    .font(PPFonts.caption(11))
                    .tracking(1.2)
                    .foregroundStyle(PPColors.textTertiary)

                Spacer()

                Button {
                    isRestartHelpPresented = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PPColors.accentYellow)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restart mode help")
                .popover(isPresented: $isRestartHelpPresented) {
                    RestartModeHelpView()
                        .presentationCompactAdaptation(.popover)
                }
            }

            Picker(
                "Restart Mode",
                selection: Binding(
                    get: { block.restartMode },
                    set: { newVal in
                        var u = block
                        u.restartMode = newVal
                        onBlockChange(u)
                    }
                )
            ) {
                ForEach(PracticeBlock.RestartMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
        }
        .pickerStyle(.segmented)
    }

    private var estimatedDuration: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 11))
            Text("Est: \(Formatters.clock(block.estimatedDuration))")
                .font(PPFonts.mono(12))
        }
        .foregroundStyle(PPColors.textTertiary)
        .frame(maxWidth: .infinity)
    }

    private func substantialStepper(label: String, value: Int, range: ClosedRange<Int>, step: Int, suffix: String, onChange: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(PPFonts.caption(10))
                .tracking(1.2)
                .foregroundStyle(PPColors.textTertiary)

            HStack(spacing: 8) {
                Button {
                    let newVal = value - step
                    if newVal >= range.lowerBound { onChange(newVal) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(PPColors.textSecondary)
                }
                .buttonStyle(.plain)

                Text("\(value)\(suffix)")
                    .font(PPFonts.monoLarge(18))
                    .foregroundStyle(PPColors.textPrimary)
                    .frame(minWidth: 44)

                Button {
                    let newVal = value + step
                    if newVal <= range.upperBound { onChange(newVal) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(PPColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }
}

private struct RestartModeHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Restart Mode")
                .font(PPFonts.headline(16))
                .foregroundStyle(PPColors.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(PracticeBlock.RestartMode.allCases, id: \.self) { mode in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PPColors.accentYellow)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.label)
                                .font(PPFonts.headline(14))
                                .foregroundStyle(PPColors.textPrimary)
                            Text(mode.helpText)
                                .font(PPFonts.body(13))
                                .foregroundStyle(PPColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 310)
        .background(PPColors.card)
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
