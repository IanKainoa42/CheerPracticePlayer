# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Project uses XcodeGen. Regenerate after changing `project.yml`:
```bash
xcodegen generate
```

Build and run on simulator:
```bash
xcodebuild -project CheerPracticePlayer.xcodeproj -scheme CheerPracticePlayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' build
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/CheerPracticePlayer.app && xcrun simctl launch booted com.ianrichardson.CheerPracticePlayer
```

Run tests:
```bash
xcodebuild test -project CheerPracticePlayer.xcodeproj -scheme CheerPracticePlayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1'
```

## Architecture

iPhone-first SwiftUI app. iOS 18.0+, Swift 5. No SPM dependencies — all first-party frameworks.

### Domain Model Flow

`ImportedMix` (audio file) → `PracticeSection` (time range within the mix) → `PracticeBlock` (section + reps/rest/lead-in config) → `PrototypeSession` (collection of sections and blocks for one team).

Sections are time ranges (start/end) within the mix audio. Blocks reference a section and add practice parameters (reps, rest windows, lead-in countdown, metronome toggle, restart mode). Sections auto-clamp to mix duration when a mix is attached.

### Runtime Playback

`SessionRunnerState` — pure value-type state machine tracking current block index, rep count, and phase (`idle` → `playing` → `breakCountdown`/`leadIn` → `complete`). No timers or side effects.

`LiveSessionController` — `@Observable @MainActor` controller that owns the runner state and an `AudioPlaybackEngine`. Bridges UI actions to runner state mutations + audio playback. Injectable via `AudioPlaybackControlling` protocol for testing.

`AudioPlaybackEngine` — `AVAudioPlayer` wrapper. Plays time-bounded segments using `currentTime` seek + `DispatchWorkItem` auto-stop.

### Tab Structure

`RootTabView` wires three tabs:
- **Home** — read-only session summary
- **Builder** — import mix, edit section markers (slider-based start/end), configure blocks (reps/rest/lead-in/restart mode/metronome)
- **Run** — live playback controls, phase display, play/pause/skip/restart

State flows down from `CheerPracticePlayerApp` via `@State session` and `LiveSessionController`. Builder mutates session via `@Binding`; changes sync to controller via `.onChange`.

### Test Approach

Tests use `FakeAudioPlayer` (in-file test double conforming to `AudioPlaybackControlling`) to verify controller behavior without real audio. Tests cover: playback initiation, block skip/restart, section clamping, session mutation (upsert/remove), block duration math, runner state machine transitions.
