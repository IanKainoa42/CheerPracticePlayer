import SwiftUI

struct HomeView: View {
    let session: PrototypeSession

    var body: some View {
        NavigationStack {
            List {
                Section("Current Team") {
                    LabeledContent("Team", value: session.teamName)
                    LabeledContent("Mix", value: session.mixName)
                    LabeledContent("Sections", value: "\(session.sections.count)")
                    LabeledContent("Blocks", value: "\(session.blocks.count)")
                    LabeledContent("Estimated Time", value: Formatters.clock(session.totalEstimatedDuration))
                }

                Section("Imported Audio") {
                    if let mix = session.mix {
                        LabeledContent("File", value: mix.displayName)
                        LabeledContent("Duration", value: Formatters.clock(mix.duration))
                        Text(mix.localPath)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("No mix imported yet. Use Builder to bring in a real team mix and mark sections.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Why this exists") {
                    Text("Run practice from the team's actual mix with automatic section repeats, timed breaks, lead-ins, and sync support.")
                        .font(.body)
                }
            }
            .navigationTitle("Cheer Practice")
        }
    }
}
