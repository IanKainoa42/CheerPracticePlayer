import SwiftUI

struct HomeView: View {
    let session: PrototypeSession

    var body: some View {
        NavigationStack {
            List {
                Section("Current Team") {
                    LabeledContent("Team", value: session.teamName)
                    LabeledContent("Mix", value: session.mixName)
                    LabeledContent("Blocks", value: "\(session.blocks.count)")
                    LabeledContent("Estimated Time", value: Formatters.clock(session.totalEstimatedDuration))
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
