import SwiftUI

struct PracticeBuilderView: View {
    @Binding var session: PrototypeSession
    @Binding var runner: SessionRunnerState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Team", value: session.teamName)
                    LabeledContent("Mix", value: session.mixName)
                    LabeledContent("Total Time", value: Formatters.clock(session.totalEstimatedDuration))
                }

                Section("Blocks") {
                    ForEach($session.blocks) { $block in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(block.title)
                                .font(.headline)

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
            .navigationTitle("Builder")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset Run") {
                        runner = SessionRunnerState(template: session)
                    }
                }
            }
        }
    }
}
