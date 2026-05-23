# CheerPracticePlayer

## Project Overview
CheerPracticePlayer is an iPhone-first SwiftUI prototype that enables cheer coaches to set up and run structured practice flows (programmable practice playback). The app allows coaches to load a team mix, define routine sections, program reps/rest windows/lead-ins, and run a live practice session.

The project is managed using XcodeGen. The deployment target is iOS 18.0, using Swift 5.0, and has Mac Catalyst enabled. The architecture relies on pure value-type state machines (`SessionRunnerState`), `@Observable` controllers (`LiveSessionController`), and an `AudioPlaybackEngine` wrapping `AVAudioPlayer`.

## Building and Running
The Xcode project (`CheerPracticePlayer.xcodeproj`) is generated. **Never hand-edit the `.xcodeproj`.**

**Generate the project (after `project.yml` edits):**
```bash
xcodegen generate
```

**Build for Mac Catalyst (no local signing required):**
```bash
xcodebuild build \
  -project CheerPracticePlayer.xcodeproj \
  -scheme CheerPracticePlayer \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -toolchain XcodeDefault \
  CODE_SIGNING_ALLOWED=NO
```

**Run Unit Tests on Mac Catalyst:**
```bash
xcodebuild test \
  -project CheerPracticePlayer.xcodeproj \
  -scheme CheerPracticePlayer \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -toolchain XcodeDefault \
  CODE_SIGNING_ALLOWED=NO
```

## Development Conventions
- **Targeting:** Always target Mac Catalyst or real iOS/iPadOS devices for builds and testing. Do not use the iOS Simulator unless explicitly requested.
- **Simplicity & Frameworks:** Keep the prototype simple using SwiftUI and first-party Apple frameworks only. Seek approval before adding new dependencies.
- **Ergonomics:** Prioritize coach-at-practice ergonomics (large controls, fast trimming/seek, minimal interaction during live runs) over generic app polish.
- **Testing:** Add or update unit tests in `Tests/CheerPracticePlayerTests.swift` before making behavior changes. The test suite uses `FakeAudioPlayer` as an in-file test double.
- **Project Config:** Edit `project.yml` when bumping build/version or making project changes, then run `xcodegen generate`.
- **Fragile Areas:** Be careful modifying Audio segment playback, Global timeline/seek (shared between Builder and Live views), Runner state machine, Trim/playhead UI, and Mix persistence/import. Treat runner changes as pure logic changes and ensure tests are updated.
