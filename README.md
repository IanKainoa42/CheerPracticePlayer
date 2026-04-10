# CheerPracticePlayer

Programmable practice playback for cheer teams.

CheerPracticePlayer is an iPhone-first SwiftUI prototype that lets coaches:
- load a team mix
- define routine sections
- program reps, rest windows, and lead-ins
- run a live practice session with minimal phone interaction
- optionally add a metronome overlay on problem sections

## Prototype goal

Prove that coaches can set up and run a structured practice flow faster than manually scrubbing a track.

## Planned v1 loop

1. Import a team mix
2. Mark section start/end times
3. Build practice blocks with reps/rest/lead-in
4. Run the practice session in a large-control live mode
5. Save the template for reuse

## Repo layout

- `App/` — app entry and root shell
- `Features/` — product feature modules
- `Models/` — shared domain models
- `Shared/` — reusable UI and helpers
- `Tests/` — unit tests for prototype logic
- `docs/` — product docs and implementation plan

## Local development

Generate the project:

```bash
xcodegen generate
```

Show available simulators:

```bash
xcodebuild -showdestinations -project CheerPracticePlayer.xcodeproj -scheme CheerPracticePlayer
```

Run tests using an installed simulator:

```bash
xcodebuild test   -project CheerPracticePlayer.xcodeproj   -scheme CheerPracticePlayer   -destination 'platform=iOS Simulator,name=<DEVICE>,OS=<VERSION>'
```
