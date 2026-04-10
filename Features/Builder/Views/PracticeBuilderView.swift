import SwiftUI

struct PracticeBuilderView: View {
    @Binding var session: PrototypeSession
    let onResetRun: () -> Void

    @State private var isImportingMix = false
    @State private var importErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                mixSection
                sectionMarkersSection
                blocksSection
            }
            .navigationTitle("Builder")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Import Mix") {
                        isImportingMix = true
                    }

                    Button("Reset Run") {
                        onResetRun()
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
        }
    }

    private var mixSection: some View {
        Section("Mix") {
            LabeledContent("Team", value: session.teamName)
            LabeledContent("Mix", value: session.mixName)
            LabeledContent("Mix Length", value: Formatters.clock(session.mixDuration))

            if let mix = session.mix {
                Text(mix.localPath)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Import a real team audio file to start placing section markers.")
                    .foregroundStyle(.secondary)
            }

            Button {
                isImportingMix = true
            } label: {
                Label(session.mix == nil ? "Import Team Mix" : "Replace Team Mix", systemImage: "square.and.arrow.down")
            }
        }
    }

    private var sectionMarkersSection: some View {
        Section("Section Markers") {
            if session.sections.isEmpty {
                Text("No sections yet. Import a mix, then add a section marker.")
                    .foregroundStyle(.secondary)
            }

            ForEach(session.sections) { section in
                SectionEditorCard(
                    section: section,
                    maxDuration: max(session.mixDuration, 1),
                    onChange: { updated in
                        session.upsertSection(updated)
                    },
                    onDelete: {
                        session.removeSection(id: section.id)
                    },
                    onAddBlock: {
                        session.addBlock(for: section)
                    }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Button {
                session.addSection(PracticeSection.blank(totalDuration: max(session.mixDuration, 32)))
            } label: {
                Label("Add Section", systemImage: "plus.circle")
            }
            .disabled(session.mix == nil && session.mixDuration == 0)
        }
    }

    private var blocksSection: some View {
        Section("Blocks") {
            if session.blocks.isEmpty {
                Text("Add a section marker, then turn it into a practice block.")
                    .foregroundStyle(.secondary)
            }

            ForEach($session.blocks) { $block in
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Block Title", text: $block.title)
                        .textFieldStyle(.roundedBorder)

                    Text(block.section.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Stepper("Reps: \(block.reps)", value: $block.reps, in: 1...12)
                    Stepper("Rest: \(block.restSeconds)s", value: $block.restSeconds, in: 0...180, step: 5)
                    Stepper("Lead-in: \(block.leadInSeconds)s", value: $block.leadInSeconds, in: 0...32)

                    Picker("Restart", selection: $block.restartMode) {
                        ForEach(PracticeBlock.RestartMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Metronome overlay", isOn: $block.metronomeEnabled)

                    Text("Estimated block time: \(Formatters.clock(block.estimatedDuration))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            .onDelete { session.blocks.remove(atOffsets: $0) }
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

private struct SectionEditorCard: View {
    let section: PracticeSection
    let maxDuration: TimeInterval
    let onChange: (PracticeSection) -> Void
    let onDelete: () -> Void
    let onAddBlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            .textFieldStyle(.roundedBorder)

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
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Start", value: Formatters.clock(section.startTime))
                Slider(
                    value: Binding(
                        get: { section.startTime },
                        set: { newValue in
                            var updated = section
                            updated.startTime = min(newValue, updated.endTime)
                            onChange(updated)
                        }
                    ),
                    in: 0...maxDuration
                )

                LabeledContent("End", value: Formatters.clock(section.endTime))
                Slider(
                    value: Binding(
                        get: { section.endTime },
                        set: { newValue in
                            var updated = section
                            updated.endTime = max(newValue, updated.startTime)
                            onChange(updated)
                        }
                    ),
                    in: 0...maxDuration
                )
            }

            Text("Duration: \(Formatters.clock(section.duration))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    onAddBlock()
                } label: {
                    Label("Add Block", systemImage: "plus.square.on.square")
                }

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private extension PracticeSection.SectionType {
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
}
