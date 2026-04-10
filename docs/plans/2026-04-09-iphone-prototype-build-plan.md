# CheerPracticePlayer iPhone Prototype Build Plan

> For Hermes: use this as the execution map for the first believable prototype.

## Goal
Build an iPhone-first SwiftUI prototype that proves coaches can create and run practice blocks around a team mix with almost no live interaction.

## Architecture
Use a local-first SwiftUI app generated with XcodeGen. Keep the first pass offline, with simple domain models and a single prototype session view model. Defer real audio import complexity until the builder and run flow feel right.

## Stack
- SwiftUI
- Observation / lightweight state container
- XCTest
- XcodeGen

## Phase 1 — believable shell
1. Scaffold SwiftUI app with XcodeGen and generated Info.plist settings.
2. Add domain models for sections, blocks, and templates.
3. Build a root tab shell: Home, Builder, Live Run.
4. Seed the app with realistic sample practice data.
5. Add tests for block duration totals and run-state transitions.

## Phase 2 — builder interaction
1. Replace static builder content with editable block controls.
2. Support add, duplicate, delete, reorder.
3. Show total session duration and next-up previews.
4. Persist prototype sessions locally.

## Phase 3 — audio loop
1. Integrate AVAudioPlayer or AVPlayer wrapper.
2. Start playback from selected section timestamps.
3. Stop at section end.
4. Add break countdown and lead-in cue.
5. Validate restart timing with a real mix.

## Phase 4 — metronome + polish
1. Add click overlay per block.
2. Tune relative mix/click volume.
3. Add larger floor-safe controls.
4. Test Bluetooth speaker behavior and interruptions.

## Validation checklist
- Create a 5-rep tumble block in under 2 minutes
- Run a full sample session with no manual scrubbing
- Restart a block with one tap
- Toggle metronome on one block only
- Confirm at least one real coach can understand the live run screen instantly
