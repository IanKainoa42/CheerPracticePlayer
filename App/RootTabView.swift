import SwiftUI

struct RootTabView: View {
    @Binding var session: PrototypeSession
    let controller: LiveSessionController
    let mixLibrary: MixLibraryStore

    var body: some View {
        TabView {
            HomeView(session: session)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            PracticeBuilderView(session: $session, mixLibrary: mixLibrary) {
                controller.syncSession(session)
            }
            .tabItem {
                Label("Builder", systemImage: "slider.horizontal.3")
            }

            LiveRunView(controller: controller)
                .tabItem {
                    Label("Run", systemImage: "play.circle")
                }
        }
        .onAppear {
            controller.syncSession(session)
        }
        .onChange(of: session) { _, newValue in
            controller.syncSession(newValue)
        }
    }
}
