# Learnings

## 2026-05-19 — Empty-state UI code never fires while sample session is seeded at boot

- **Category:** correction
- **What happened:** Added a `session.mix == nil` empty-state branch to PracticeBuilderView and shipped it. User said the screen "looks exactly the same." Root cause: `CheerPracticePlayerApp.init()` hardcodes `PrototypeSession.sample`, which seeds a fake "Blackout Worlds Mix" + 3 sections. `session.mix` is therefore never `nil` on fresh launch — empty branch is unreachable.
- **Rule:** Before shipping any empty/zero-state branch on this app, verify the app's init path actually allows `session.mix == nil`. Today that means either using `PrototypeSession.empty` or providing a UI path to clear the mix. Don't claim an empty-state change is visible if the app boots with a seeded sample.

## 2026-04-11 — Always use .buttonStyle(.borderless) for Buttons inside SwiftUI List rows

- **Category:** correction
- **What happened:** Shipped SectionEditorCard with Button views inside a List row without `.buttonStyle(.borderless)`. SwiftUI expanded the Delete button's hit area to the entire row, so tapping anywhere on the card triggered deletion.
- **Rule:** Always add `.buttonStyle(.borderless)` to every Button inside a SwiftUI List row. Without it, List expands button tap targets to the full row width.

## 2026-05-20 — Don't mix "current rep" with "completion state" in Live UI

- **Category:** correction
- **What happened:** When the session reached `.complete`, the Live tab simultaneously showed "SESSION DONE" hero and "Rep 1 of 3" sub-label because the cue card always renders `currentRep` of the current block. Also: the bottom action bar's NEXT button advanced to the next *block*, not the next *rep*, but was labeled ambiguously, and PREVIOUS/NEXT block jumps duplicated functionality already available by tapping rows in the Block Queue.
- **Rule:**
  1. In `.complete` phase, suppress per-block rep counters and per-section subtitles — show only the completion state.
  2. Pips represent **cumulative reps attempted per block across the session**, not just `currentRep`. Maintain a `repsAttempted[blockID] -> Int` map on the controller/runner so jumping back and forth preserves progress. Pips persist when revisiting a block.
  3. If a list view lets you tap to jump (e.g., Block Queue rows), don't also ship Previous/Next buttons that do the same navigation. Strip the redundant buttons.
  4. Action button labels must name the unit they act on. Never use "NEXT" alone — "NEXT BLOCK" or "NEXT REP" only.

## 2026-05-20 — Section renames silently failed to reach Live tab

- **Category:** correction
- **What happened:** Renaming a section in Builder Step 3 did not update the block title shown in Live (hero, cue card, queue row). `PrototypeSession.upsertSection` had `if updated.title.isEmpty { updated.title = normalized.name }`, but blocks are seeded with a non-empty title at creation, so the guard never fired.
- **Rule:** Block title is a derived mirror of section name (no UI edits it independently). On `upsertSection`, set `block.title = normalized.name` unconditionally. If a future feature adds an independent block-title editor, revisit this and gate the propagation on "title currently matches the old section name."

## 2026-05-20 — Unified play/pause CTA dead-ended the session on pause-during-break

- **Category:** correction
- **What happened:** After the unified-status-card refactor (c5df974), pausing during a `.breakCountdown` phase (only reachable via tab-switch auto-pause from RootTabView) left the runner phase as `.breakCountdown(N)` and the countdown timer cancelled. On resume, `LiveSessionController.resumePlayback` computed `remainingAudio ≈ 0` from the just-ended segment and called `onSectionPlaybackFinished`, which guards on `phase == .playing` and silently returned. Net: play button became inert; the rest never resumed.
- **Rule:** `resumePlayback` must branch on `runner.phase`: `.breakCountdown` → restart the countdown timer with the preserved seconds-remaining (do not touch audio); `.idle`/`.complete` → clear `isPaused` and no-op; only `.playing` falls through to `audioPlayer.resumeUntil`. Regression test: `testLiveSessionController_ResumeAfterPauseDuringBreak_RestartsCountdownAndDoesNotReplayAudio` in Tests/CheerPracticePlayerTests.swift.

## 2026-05-20 — Status card lied "Playing" while paused

- **Category:** correction
- **What happened:** `LiveRunView.phaseLabel`, `isActivePhase`, and `phaseStatusColor` switched on `controller.runner.phase` alone, ignoring `controller.isPaused`. Result: while paused, the card label read "Playing", the green pulse ring kept animating, and the inner circle stayed green — even though the icon (gated correctly via `mainActionIcon`) had switched to `play.fill`. Three signals contradicted each other.
- **Rule:** Every view-level computed property that reads `runner.phase` must short-circuit on `controller.isPaused` first, matching the existing pattern in `mainActionIcon`/`mainActionColor`/`mainActionForeground`. When adding new phase-derived view properties, copy that gate.

## 2026-05-20 — MixLibraryStore silently nuked the library on any decode failure

- **Category:** correction
- **What happened:** `load()` was `mixes = (try? JSONDecoder().decode(...)) ?? []`. Any decode failure (future schema change, partial corruption, etc.) would silently start the store empty; the next `persist()` would atomically overwrite the only good copy with `[]`. v1.0 build 2 ships to App Store soon — this was a one-bad-byte-loses-all-saved-mixes risk.
- **Rule:** On decode failure, rename the file to `<name>.bak-<ISO8601 timestamp>` via `FileManager.moveItem` BEFORE starting empty. Persist then writes a new file; the bak preserves the original for forensics or future migration. Tests `testMixLibraryStore_CorruptFile_IsBackedUpAndStoreStartsEmpty` and `testMixLibraryStore_ValidFile_LoadsMixesIntact` pin this. To make the test possible, `MixLibraryStore.init` now accepts an optional `fileURL` override.

## 2026-05-20 — Pulse-ring repeatForever animation starved the section-end Timer

- **Category:** correction
- **What happened:** After the unified-status-card refactor (c5df974), the cue card's pulse ring uses `.animation(.easeInOut(...).repeatForever(autoreverses: true), value: pulseScale)`. On iPadOS 18, a SwiftUI `repeatForever` animation pins the main RunLoop into tracking mode for the duration of the animation. `Timer.scheduledTimer(withTimeInterval:repeats:block:)` registers in `.default` RunLoop mode, which is preempted while the loop is in tracking mode — so `playbackEndTimer` (and the countdown / playhead / session timers) silently never fired. Net symptom on iPad: tapping Play started the section but audio rolled past the section endTime and kept playing into the rest of the track. The `DispatchWorkItem` auto-stop in `AudioPlaybackEngine` also missed the pause because it captured `[weak player]` — a stale reference if anything between schedule and fire replaced the AVAudioPlayer.
- **Rule:** Any `Timer` whose firing is load-bearing for app correctness MUST be registered with `RunLoop.main.add(_, forMode: .common)` — not `Timer.scheduledTimer`. `LiveSessionController.makeCommonModeTimer(...)` centralizes this. Also: capture `[weak self]` (the engine) in `AudioPlaybackEngine.scheduleAutoStop` so `self?.player?.pause()` always targets the current player.
- **Detection:** If you ever see "audio plays past section end" or "countdown doesn't tick on Live tab" — first check whether the affected RunLoop-driven Timer is in `.common` mode. Pulse/breathing/ring animations elsewhere in the same view can starve `.default` timers.

## 2026-05-22 — Shadowing release install masks debug build changes

- **Category:** correction
- **What happened:** Built Mac Catalyst debug, launched the `.app` from DerivedData, told user to test. User reported "same thing" — they were actually launching `/Applications/CheerPracticePlayer.app` (a TestFlight/release iOS-on-Mac install from May 20) via the dock/Launchpad, not the fresh DerivedData build.
- **Rule:** Before declaring an iOS/Catalyst rebuild "ready to test," check `find /Applications ~/Applications -name "<App>.app"` and `xcrun devicectl list devices` for shadowing installs. If a release/TestFlight install exists, install to a real device (`xcrun devicectl device install app --device <id> <path-to-.app>` then `process launch`) rather than relying on `open` of the DerivedData bundle — the user's dock/home-screen icon points at the older one.

## 2026-05-22 — Hold-to-pause: branch view by phase, don't simultaneousGesture a Button

- **Category:** best_practice
- **What happened:** Wanted hold-to-pause guard on the Live cue card during active play (tap = no-op, long-press = pause). First instinct: keep the existing `Button(action:)` and add `.simultaneousGesture(LongPressGesture(...))`. SwiftUI `Button` consumes touch-up before LongPressGesture resolves, so the long-press fires unreliably.
- **Rule:** Use a `@ViewBuilder` branch on phase: during the locked state, render the same content as a plain view with `.onTapGesture` (warning haptic) + `.onLongPressGesture(minimumDuration: 0.6)` (action); during unlocked state, render the existing `Button`. Extract the visual body into a separate function so both branches share it. Add `.sensoryFeedback(.warning, trigger: Int)` driven by a `@State` counter incremented in onTap for the haptic nudge.

## 2026-05-22 — Tests can encode the bug you're being asked to fix

- **Category:** correction
- **What happened:** Fixed `pausePlayback()` to no-op when phase is idle (the actual user-facing bug — tab-switch was eating the first Live tap). Test `testLiveSessionController_ResumeFromIdleWhilePaused_ClearsPausedFlagAndIsNoOp` failed because it asserted the OLD (broken) behavior was correct.
- **Rule:** When a unit test fails after a bug fix that the user explicitly requested, read the test first — it may be enshrining the bug. If so, rewrite the test to assert the new correct behavior, with a comment explaining the regression. Don't revert the fix to make the test pass.
