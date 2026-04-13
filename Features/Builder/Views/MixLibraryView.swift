import SwiftUI

struct MixLibraryView: View {
    let library: MixLibraryStore
    let onSelect: (SavedMix) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if library.mixes.isEmpty {
                    ContentUnavailableView(
                        "No Saved Mixes",
                        systemImage: "music.note.list",
                        description: Text("Import a mix and define sections, then save it to your library for reuse.")
                    )
                } else {
                    List {
                        ForEach(library.mixes) { saved in
                            Button {
                                onSelect(saved)
                                dismiss()
                            } label: {
                                MixLibraryRow(savedMix: saved)
                            }
                            .buttonStyle(.borderless)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                library.remove(id: library.mixes[index].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mix Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct MixLibraryRow: View {
    let savedMix: SavedMix

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(savedMix.displayName)
                .font(.headline)

            HStack(spacing: 16) {
                Label(Formatters.clock(savedMix.duration), systemImage: "clock")
                Label("\(savedMix.sectionCount) sections", systemImage: "scissors")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
