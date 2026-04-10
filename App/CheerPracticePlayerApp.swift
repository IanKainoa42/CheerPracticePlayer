import SwiftUI

@main
struct CheerPracticePlayerApp: App {
    @State private var session = PrototypeSession.sample
    @State private var runner = SessionRunnerState(template: PrototypeSession.sample)

    var body: some Scene {
        WindowGroup {
            RootTabView(session: $session, runner: $runner)
        }
    }
}
