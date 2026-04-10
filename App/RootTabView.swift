import SwiftUI

struct RootTabView: View {
    @Binding var session: PrototypeSession
    @Binding var runner: SessionRunnerState

    var body: some View {
        TabView {
            HomeView(session: session)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            PracticeBuilderView(session: $session, runner: $runner)
                .tabItem {
                    Label("Builder", systemImage: "slider.horizontal.3")
                }

            LiveRunView(session: session, runner: $runner)
                .tabItem {
                    Label("Run", systemImage: "play.circle")
                }
        }
        .onChange(of: session) { _, newValue in
            runner.syncTemplate(newValue)
        }
    }
}
