import SwiftUI

@main
struct CheerPracticePlayerApp: App {
    @State private var session = PrototypeSession.sample
    @State private var controller = LiveSessionController(session: PrototypeSession.sample)
    @State private var mixLibrary = MixLibraryStore()

    var body: some Scene {
        WindowGroup {
            RootTabView(session: $session, controller: controller, mixLibrary: mixLibrary)
        }
    }
}
