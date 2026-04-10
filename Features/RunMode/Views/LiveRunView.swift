import SwiftUI

struct LiveRunView: View {
    let session: PrototypeSession
    @Binding var runner: SessionRunnerState

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let block = runner.currentBlock {
                    VStack(spacing: 8) {
                        Text(block.title)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)

                        Text(block.section.name)
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Text("Rep \(max(runner.currentRep, 1)) of \(block.reps)")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    VStack(spacing: 12) {
                        Label(phaseLabel, systemImage: phaseIcon)
                            .font(.title2.weight(.semibold))
                        Text("Metronome: \(block.metronomeEnabled ? "On" : "Off")")
                            .foregroundStyle(.secondary)
                        Text("Block time: \(Formatters.clock(block.estimatedDuration))")
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 14) {
                        Button("Start / Advance") {
                            runner.advance()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        HStack(spacing: 12) {
                            Button("Break") { runner.beginBreak() }
                                .buttonStyle(.bordered)
                            Button("Lead-In") { runner.beginLeadIn() }
                                .buttonStyle(.bordered)
                        }

                        HStack(spacing: 12) {
                            Button("Restart Block") { runner.restartBlock() }
                                .buttonStyle(.bordered)
                            Button("Skip Block") { runner.skipBlock() }
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    ContentUnavailableView("No Blocks", systemImage: "music.note.list", description: Text("Create at least one practice block in Builder."))
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Live Run")
        }
    }

    private var phaseLabel: String {
        switch runner.phase {
        case .idle:
            return "Ready"
        case .playing:
            return "Playing"
        case .breakCountdown(let secondsRemaining):
            return "Break: \(secondsRemaining)s"
        case .leadIn(let secondsRemaining):
            return "Lead-In: \(secondsRemaining)s"
        case .complete:
            return "Session Complete"
        }
    }

    private var phaseIcon: String {
        switch runner.phase {
        case .idle: return "pause.circle"
        case .playing: return "play.circle.fill"
        case .breakCountdown: return "timer"
        case .leadIn: return "metronome"
        case .complete: return "checkmark.circle.fill"
        }
    }
}
