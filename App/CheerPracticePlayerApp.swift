import SwiftUI

@main
struct CheerPracticePlayerApp: App {
    @State private var session: PrototypeSession
    @State private var controller: LiveSessionController
    @State private var mixLibrary = MixLibraryStore()
    @State private var requestImportAfterOnboarding = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
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
            ZStack {
                RootTabView(
                    session: $session,
                    controller: controller,
                    mixLibrary: mixLibrary,
                    audioEngine: audioEngine,
                    requestImportAfterOnboarding: $requestImportAfterOnboarding
                )

                if !hasCompletedOnboarding && mixLibrary.mixes.isEmpty {
                    OnboardingView(
                        onStart: {
                            hasCompletedOnboarding = true
                            requestImportAfterOnboarding = true
                        },
                        onSkip: {
                            hasCompletedOnboarding = true
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: hasCompletedOnboarding)
            .onAppear {
                if !mixLibrary.mixes.isEmpty {
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}
