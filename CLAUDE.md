# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

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

CheerPracticePlayer is an iPhone-first SwiftUI app for programmable practice playback. Deployment target is iOS 18.0, Swift version is 5.0, and the app target has Mac Catalyst support enabled.

### Domain Model Flow

`ImportedMix` (audio file) -> `PracticeSection` (time range within the mix) -> `PracticeBlock` (section + reps/rest/lead-in config) -> `PrototypeSession` (collection of sections and blocks for one team).

Sections are time ranges within the mix. Blocks reference a section and add practice parameters: reps, rest windows, lead-in countdown, metronome toggle, and restart mode. Sections auto-clamp to mix duration when a mix is attached.

### Runtime Playback

- `SessionRunnerState` is the pure value-type state machine for block index, rep count, and phase (`idle` -> `playing` -> `breakCountdown`/`leadIn` -> `complete`). Keep timers and side effects out of it.
- `LiveSessionController` is an `@Observable @MainActor` controller that owns runner state and an `AudioPlaybackControlling` implementation. UI actions should pass through here instead of talking directly to audio playback.
- `AudioPlaybackEngine` wraps `AVAudioPlayer`, seeks to bounded segment starts, and schedules auto-stop with a `DispatchWorkItem`.

### Tab Structure

`RootTabView` wires three tabs:
- Home: read-only session summary.
- Builder: import mix, edit section markers, configure blocks, and save/load mixes.
- Run: live playback controls, phase display, play/pause/skip/restart.

State flows down from `CheerPracticePlayerApp` via `@State session` and `LiveSessionController`. Builder mutates session through bindings; changes sync back to the controller with `.onChange`.

## Test Approach

Tests live in `Tests/CheerPracticePlayerTests.swift` and use `FakeAudioPlayer` as an in-file `AudioPlaybackControlling` test double. Existing coverage focuses on playback initiation, block skip/restart, section clamping, session mutation, block duration math, and runner state transitions.

For behavior changes, add or update unit tests first, then run the Mac Catalyst test command above. Use simulator tests only when Ian explicitly asks for simulator validation.

## Known Fragile Areas

| Area | Files | Why fragile | Rule |
|---|---|---|---|
| Audio segment playback | `Shared/AudioPlaybackEngine.swift`, `Shared/LiveSessionController.swift` | Practice flow depends on exact seek/start/stop timing and correct block boundaries. | Keep playback state changes centralized in `LiveSessionController`; preserve tests around seek times and play counts. |
| Runner state machine | `Models/SessionRunnerState.swift`, `Tests/CheerPracticePlayerTests.swift` | Off-by-one rep/block transitions can silently break live practice sessions. | Treat runner changes as pure logic changes with unit tests first. |
| Trim/playhead UI | `Features/Builder/Views/WaveformTrimmerView.swift`, `Features/Builder/Views/PracticeBuilderView.swift` | Recent work iterated on trimming and playhead behavior; small gesture changes can make section editing unusable. | Preserve visible handles, tap-to-seek, playhead rendering, and minimum selection constraints. |
| Mix persistence/import | `Shared/MixLibraryStore.swift`, `Shared/MixImportService.swift`, `Models/SavedMix.swift` | Coaches need saved reusable mixes/templates; path/bookmark mistakes can strand imported audio. | Avoid destructive migrations; test save/load paths when touching persistence. |
| XcodeGen project config | `project.yml`, `CheerPracticePlayer.xcodeproj` | The `.xcodeproj` is generated; manual project edits can be overwritten. | Edit `project.yml`, run `xcodegen generate`, then build. |

## Repo / Tracking

- GitHub repo: `IanKainoa42/CheerPracticePlayer`
- Local path: `~/Projects/CheerPracticePlayer`
- Linear project: `CheerPracticePlayer` in Ianplus / IAN
