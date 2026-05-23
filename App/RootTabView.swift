import SwiftUI

struct RootTabView: View {
    @Binding var session: PrototypeSession
    let controller: LiveSessionController
    let mixLibrary: MixLibraryStore
    let audioEngine: AudioPlaybackEngine

    @State private var selectedTab: Int
    @State private var requestImportFromBuild = false

    init(session: Binding<PrototypeSession>, controller: LiveSessionController, mixLibrary: MixLibraryStore, audioEngine: AudioPlaybackEngine) {
        self._session = session
        self.controller = controller
        self.mixLibrary = mixLibrary
        self.audioEngine = audioEngine
        // Land on Library when there are saved mixes; otherwise jump to Build so first-import has no extra tap.
        let hasMixes = !mixLibrary.mixes.isEmpty
        self._selectedTab = State(initialValue: hasMixes ? 0 : 1)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                session: session,
                library: mixLibrary,
                onSelectMix: { saved in
                    loadFromLibrary(saved)
                    selectedTab = 1
                },
                onImportTapped: {
                    requestImportFromBuild = true
                    selectedTab = 1
                }
            )
            .tabItem {
                Label("Library", systemImage: "tray.full")
            }
            .tag(0)

            PracticeBuilderView(
                session: $session,
                mixLibrary: mixLibrary,
                audioEngine: audioEngine,
                requestImport: $requestImportFromBuild
            )
            .tabItem {
                Label("Build", systemImage: "slider.horizontal.3")
            }
            .tag(1)

            LiveRunView(controller: controller)
                .tabItem {
                    Label("Live", systemImage: "play.circle.fill")
                }
                .tag(2)
        }
        .preferredColorScheme(.dark)
        .tint(PPColors.accentYellow)
        .onAppear {
            controller.syncSession(session)
            configureTabBarAppearance()
        }
        .onChange(of: session) { _, newValue in
            controller.syncSession(newValue)
        }
    }

    private func loadFromLibrary(_ savedMix: SavedMix) {
        session.mix = savedMix.mix
        session.sections = savedMix.sections
        session.blocks = []
        for section in savedMix.sections {
            session.addBlock(for: section)
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.06, alpha: 1.0)
        appearance.shadowColor = .clear

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.35)
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.35)]
        itemAppearance.selected.iconColor = UIColor(PPColors.accentYellow)
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(PPColors.accentYellow)]

        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
