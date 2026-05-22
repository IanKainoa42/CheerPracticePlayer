import SwiftUI

struct HomeView: View {
    let session: PrototypeSession
    let library: MixLibraryStore
    let onSelectMix: (SavedMix) -> Void
    let onImportTapped: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                PPColors.background.ignoresSafeArea()

                if library.mixes.isEmpty {
                    emptyState
                } else {
                    libraryList
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !library.mixes.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onImportTapped) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(PPColors.accentYellow)
                        }
                        .accessibilityLabel("Import Mix")
                    }
                }
            }
        }
    }

    // MARK: - Library list

    private var libraryList: some View {
        List {
            if let activeID = session.mix?.id {
                Section {
                    ForEach(library.mixes) { saved in
                        Button {
                            onSelectMix(saved)
                        } label: {
                            MixLibraryRow(
                                savedMix: saved,
                                isActive: saved.mix.id == activeID
                            )
                        }
                        .buttonStyle(.borderless)
                    }
                    .onDelete(perform: deleteMixes)
                }
            } else {
                ForEach(library.mixes) { saved in
                    Button {
                        onSelectMix(saved)
                    } label: {
                        MixLibraryRow(savedMix: saved, isActive: false)
                    }
                    .buttonStyle(.borderless)
                }
                .onDelete(perform: deleteMixes)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func deleteMixes(at offsets: IndexSet) {
        for index in offsets {
            library.remove(id: library.mixes[index].id)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "tray.full")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(PPColors.textTertiary)

            VStack(spacing: 8) {
                Text("No Saved Mixes")
                    .font(PPFonts.title(22))
                    .foregroundStyle(PPColors.textPrimary)

                Text("Import a mix and save it here for one-tap reuse.")
                    .font(PPFonts.body(14))
                    .foregroundStyle(PPColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: onImportTapped) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .bold))
                    Text("IMPORT MIX")
                        .font(PPFonts.headline(15))
                        .tracking(1.2)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Capsule().fill(PPColors.accentYellow))
            }
            .buttonStyle(.plain)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

private struct MixLibraryRow: View {
    let savedMix: SavedMix
    let isActive: Bool

    private var markedDuration: TimeInterval {
        savedMix.sections.reduce(0) { $0 + $1.duration }
    }

    private var coveragePercent: Int {
        guard savedMix.duration > 0 else { return 0 }
        return Int((markedDuration / savedMix.duration * 100).rounded())
    }

    private var addedString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: savedMix.dateAdded)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [PPColors.accentYellow, PPColors.accentOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(savedMix.displayName)
                        .font(PPFonts.headline(16))
                        .foregroundStyle(PPColors.textPrimary)
                        .lineLimit(1)

                    if isActive {
                        Text("ACTIVE")
                            .font(PPFonts.caption(9))
                            .tracking(1.0)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(PPColors.accentYellow))
                    }
                }

                HStack(spacing: 10) {
                    Label(Formatters.clock(savedMix.duration), systemImage: "clock")
                    Label("\(savedMix.sectionCount) sections", systemImage: "scissors")
                    if savedMix.sectionCount > 0 {
                        Label("\(Formatters.clock(markedDuration)) marked", systemImage: "waveform")
                    }
                }
                .font(PPFonts.mono(11))
                .foregroundStyle(PPColors.textTertiary)

                HStack(spacing: 10) {
                    if savedMix.sectionCount > 0 {
                        Text("\(coveragePercent)% covered")
                    }
                    Text("Added \(addedString)")
                }
                .font(PPFonts.caption(10))
                .foregroundStyle(PPColors.textTertiary.opacity(0.7))
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PPColors.textTertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
