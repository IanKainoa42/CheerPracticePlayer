import SwiftUI

struct RootTabView: View {
    @Binding var session: PrototypeSession
    let controller: LiveSessionController
    let mixLibrary: MixLibraryStore

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(session: session) { tab in
                selectedTab = tab
            }
            .tabItem {
                Label("Dashboard", systemImage: "house.fill")
            }
            .tag(0)

            PracticeBuilderView(session: $session, mixLibrary: mixLibrary) {
                controller.syncSession(session)
                selectedTab = 2
            }
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
