import SwiftUI

@main
struct CheerPracticePlayerApp: App {
    @State private var session: PrototypeSession
    @State private var controller: LiveSessionController
    @State private var mixLibrary = MixLibraryStore()
    private let audioEngine: AudioPlaybackEngine

    init() {
        let initialSession = PrototypeSession.empty
        let engine = AudioPlaybackEngine()
        _session = State(initialValue: initialSession)
        _controller = State(initialValue: LiveSessionController(session: initialSession, audioPlayer: engine))
        audioEngine = engine
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(
                session: $session,
                controller: controller,
                mixLibrary: mixLibrary,
                audioEngine: audioEngine
            )
        }
    }
}
