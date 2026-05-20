# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working in this repository.

## Project Rules

- Target Mac Catalyst or real iOS/iPadOS devices for builds and dogfooding. Do not use iOS Simulator unless Ian explicitly asks for a simulator-only check.
- Project files are generated with XcodeGen. If `project.yml` changes, run `xcodegen generate` before building.
- Keep this prototype simple: SwiftUI + first-party Apple frameworks only unless Ian approves a dependency.
- Preserve coach-at-practice ergonomics: large controls, fast trimming/seek, and minimal interaction during a live run matter more than generic app polish.

## Build & Test Commands

Generate the Xcode project after `project.yml` edits:
```bash
xcodegen generate
```

Show valid destinations:
```bash
xcodebuild -showdestinations -project CheerPracticePlayer.xcodeproj -scheme CheerPracticePlayer
```

Build for Mac Catalyst without requiring a local signing certificate:
```bash
xcodebuild build \
  -project CheerPracticePlayer.xcodeproj \
  -scheme CheerPracticePlayer \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -toolchain XcodeDefault \
  CODE_SIGNING_ALLOWED=NO
```

Run unit tests on Mac Catalyst without requiring a local signing certificate:
```bash
xcodebuild test \
  -project CheerPracticePlayer.xcodeproj \
  -scheme CheerPracticePlayer \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -toolchain XcodeDefault \
  CODE_SIGNING_ALLOWED=NO
```

Build for a connected real device:
```bash
xcodebuild build \
  -project CheerPracticePlayer.xcodeproj \
  -scheme CheerPracticePlayer \
  -destination 'platform=iOS,name=<REAL_DEVICE_NAME>'
```

Current real-device destinations seen on this machine include `ianPad` and `this is ian.  `, but re-run `-showdestinations` before hard-coding a device name.

## Architecture

CheerPracticePlayer is an iPhone-first SwiftUI app for programmable practice playback. Deployment target is iOS 18.0, Swift version is 5.0. The app target has Mac Catalyst enabled (`SUPPORTS_MACCATALYST: YES`) and ships universal (`TARGETED_DEVICE_FAMILY: "1,2"`). Marketing version 1.0, current build 2 is prepped for App Store submission.

### Domain Model Flow

`ImportedMix` (audio file) -> `PracticeSection` (time range within the mix) -> `PracticeBlock` (section + reps/rest/lead-in config) -> `PrototypeSession` (collection of sections and blocks for one team).

Sections are time ranges within the mix. Blocks reference a section and add practice parameters: reps, rest windows, lead-in countdown, metronome toggle, and restart mode. Sections auto-clamp to mix duration when a mix is attached.

### Runtime Playback

- `SessionRunnerState` is the pure value-type state machine for block index, rep count, and phase (`idle` -> `playing` -> `breakCountdown`/`leadIn` -> `complete`). Keep timers and side effects out of it.
- `LiveSessionController` is an `@Observable @MainActor` controller that owns runner state and an `AudioPlaybackControlling` implementation. UI actions should pass through here instead of talking directly to audio playback.
- `AudioPlaybackEngine` wraps `AVAudioPlayer`, seeks to bounded segment starts, and schedules auto-stop with a `DispatchWorkItem`.

### Tab Structure

`RootTabView` wires three tabs:
- **Dashboard** (`HomeView`): read-only session summary with tab-jump shortcuts.
- **Build** (`PracticeBuilderView`): import mix, edit section markers, configure blocks, save/load mixes via `MixLibraryStore`.
- **Live** (`LiveRunView`): playback controls, phase display, play/pause/skip/restart, global timeline strip with seek.

State flows down from `CheerPracticePlayerApp` via `@State session` and `LiveSessionController`. Builder mutates session through bindings; changes sync back to the controller with `.onChange`. Switching tabs auto-pauses `audioEngine` so a Build-tab preview never bleeds into Live.

### Timeline Strip / Seek

Builder and Live both render a global timeline strip and accept user seek. Both paths funnel through `LiveSessionController` and `AudioPlaybackEngine.seek`, so seek logic, segment clamping, and auto-stop scheduling are shared. Treat seek changes in either view as touching the same code path.

## Test Approach

Tests live in `Tests/CheerPracticePlayerTests.swift` and use `FakeAudioPlayer` as an in-file `AudioPlaybackControlling` test double. Existing coverage focuses on playback initiation, block skip/restart, section clamping, session mutation, block duration math, and runner state transitions.

For behavior changes, add or update unit tests first, then run the Mac Catalyst test command above. Use simulator tests only when Ian explicitly asks for simulator validation.

## Known Fragile Areas

| Area | Files | Why fragile | Rule |
|---|---|---|---|
| Audio segment playback | `Shared/AudioPlaybackEngine.swift`, `Shared/LiveSessionController.swift` | Practice flow depends on exact seek/start/stop timing and correct block boundaries. | Keep playback state changes centralized in `LiveSessionController`; preserve tests around seek times and play counts. |
| Global timeline / seek | `Features/Builder/Views/PracticeBuilderView.swift`, `Features/RunMode/Views/LiveRunView.swift`, `Shared/LiveSessionController.swift`, `Shared/AudioPlaybackEngine.swift` | Builder and Live share the same seek path; a change in one can silently break the other. | Test seek + scrub from both Build and Live after any change here; verify tab-switch pause still fires. |
| Runner state machine | `Models/SessionRunnerState.swift`, `Tests/CheerPracticePlayerTests.swift` | Off-by-one rep/block transitions can silently break live practice sessions. | Treat runner changes as pure logic changes with unit tests first. |
| Trim/playhead UI | `Features/Builder/Views/WaveformTrimmerView.swift`, `Features/Builder/Views/PracticeBuilderView.swift` | Recent work iterated on trimming and playhead behavior; small gesture changes can make section editing unusable. | Preserve visible handles, tap-to-seek, playhead rendering, and minimum selection constraints. |
| Mix persistence/import | `Shared/MixLibraryStore.swift`, `Shared/MixImportService.swift`, `Models/SavedMix.swift` | Coaches need saved reusable mixes/templates; path/bookmark mistakes can strand imported audio. | Avoid destructive migrations; test save/load paths when touching persistence. |
| XcodeGen project config | `project.yml`, `CheerPracticePlayer.xcodeproj` | The `.xcodeproj` is generated; manual project edits can be overwritten. | Edit `project.yml`, run `xcodegen generate`, then build. |

## App Store / Release

- v1.0 (build 2) queued for App Store submission (summer 2026 ship queue, priority 1).
- Release artifacts in repo: `APP_STORE_LISTING.md`, `PRIVACY_POLICY.md`, `fastlane/` (Appfile, Fastfile, AuthKey.json for ASC API), `scripts/ship-testflight.sh`.
- `.appstore/capture.md` is enrolled in the global App Store screenshot LaunchAgent (`com.ianrichardson.appstore-auto`, runs 5:32am Mon–Fri). Output goes to `AppStoreScreenshots/auto/<date>/`. Never auto-uploaded; Ian reviews.
- When bumping build/version, edit `project.yml` (`CURRENT_PROJECT_VERSION`, `MARKETING_VERSION`) then `xcodegen generate` — never hand-edit the `.xcodeproj`.

## Repo / Tracking

- GitHub repo: `IanKainoa42/CheerPracticePlayer`
- Local path: `~/Projects/CheerPracticePlayer`
- Linear project: `CheerPracticePlayer` in Ianplus / IAN
