# Learnings

## 2026-05-26 — Use two-dot diff to judge whether a stale branch has anything main lacks

- **Category:** best_practice
- **What happened:** Asked to "clean up branches and merge." `git diff main...branch` (three-dot) showed a stale branch "adding" `.gitignore` rules, so I nearly cherry-picked them. But three-dot diffs against the merge-base, so it credits the branch with changes main may have independently made since. `git diff main..branch` (two-dot) revealed the `.gitignore` was byte-identical and the branch was actually *behind* main (would have reverted onboarding, the waveform trimmer, tests). Nothing to merge — just delete.
- **Rule:** Before salvaging/merging from an old branch, run two-dot `git diff main..branch` (and `--stat`) to see the real delta vs current main — not three-dot. Deletions in `main..branch --stat` mean main is ahead. A stale branch that "adds" things in three-dot may already be fully superseded.

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

## 2026-05-22 — Legacy Start/End sliders flashing before waveform (deprecated fallback)

- **Category:** correction
- **What happened:** PracticeBuilderView's `waveform` view had an if/else: when `waveformSamples.isEmpty`, it rendered a pair of legacy "Start"/"End" sliders. When samples arrived, it swapped to WaveformTrimmerView. The user saw the old sliders flash for ~half a second every time a section card mounted before audio decoded, then snap to the waveform. This is dead/deprecated UI — the trimmer is the only intended editor.
- **Rule:** When replacing one UI control with another, remove the old branch entirely. WaveformTrimmerView already renders fine with empty `samples` (background + handles + dim overlay, no bars — Canvas returns early when count == 0). Always show the trimmer; never fall back to the legacy sliders. Also deleted the unused `timeSlider(label:value:onChange:)` helper. Related memory: [[feedback_waveform_ui.md]] — waveform is sacred, but legacy non-waveform fallbacks are not the waveform and should be pruned.

## 2026-05-26 — "invalid curve name" was a Fastfile bug, not a bad key

- **Category:** correction
- **What happened:** `fastlane lanes` crashed at parse time with `OpenSSL::PKey::EC#initialize: invalid curve name`. Prior diagnosis (2026-05-25) blamed the ASC API key and prescribed regenerating it. The key is actually a valid P-256 key. Real cause: the Fastfile header used `key_filepath: "fastlane/AuthKey.json"`, but AuthKey.json is a JSON wrapper `{key_id,issuer_id,key:<PEM>}`, not a raw .p8 — fastlane fed the whole JSON blob to `OpenSSL::PKey::EC.new` → "invalid curve name".
- **Rule:** When AuthKey.json is a JSON wrapper, parse it (`JSON.parse`) and pass `key_content:` (the extracted PEM). Never point `key_filepath:` at the JSON wrapper. Verify a fix with `fastlane lanes`, not openssl (openssl accepts the extracted key regardless).

## 2026-05-26 — /ship CheerPracticePlayer: fastlane param + first-submission gotchas

- **Category:** correction / knowledge_gap
- **What happened:** /ship pipeline for v1.0 (build 8) hit three sequential failures:
  1. `ship_upload` failed at `sync_code_signing` → "No value found for 'git_url'". This repo uses **automatic signing** (CODE_SIGN_STYLE: Automatic), not fastlane match. The working `:beta` lane never used match.
  2. `ship_upload`'s `upload_to_app_store` ran precheck and died on "Precheck cannot check In-app purchases with the App Store Connect API Key" — precheck has no business in an upload-only lane.
  3. `ship_submit` failed: `upload_to_app_store` rejected option `automatic_release_after_approval` (not a valid deliver option). Then "appStoreVersions ... is not in valid state. This resource cannot be reviewed" — fastlane created an EMPTY draft review submission because the version had a missing required field.
- **Root cause of "not in valid state":** First-ever submission was missing **Content Rights Information** in App Store Connect → App Information. ASC "Add for Review" surfaced the exact error; the fastlane API error was generic.
- **Rules going forward:**
  - In `ship_upload`/`ship_submit` lanes for repos with automatic signing: do NOT call `sync_code_signing`; just `build_app(export_method: "app-store", xcargs: "-allowProvisioningUpdates")` like the `:beta` lane.
  - `upload_to_app_store` auto-release option is **`automatic_release: true`**, NOT `automatic_release_after_approval`.
  - Add `run_precheck_before_submit: false` to upload-only lanes.
  - For a generic "appStoreVersions not in valid state" on first submission, open ASC and click "Add for Review" to get the specific blocking list (Content Rights, age rating, pricing, etc.). The ASC API privacy/validation paths return PATH_ERROR with an API key — the web UI is authoritative.

## 2026-05-28 — Pip credit silently missed for short sections; pre-roll fade-in offset

- **Category:** correction
- **What happened:** User reported pips not lighting up reliably and "sessions completing midway." Root cause: `LiveSessionController.creditCurrentRepIfThresholdMet` checked `audioPlayer.currentTime - section.startTime >= 0.75 * sectionDuration`, but `AudioPlaybackEngine.playSegment` starts 0.5s early for a pre-roll fade-in. The controller's `playbackEndTimer` fired at `sectionDuration / rate` real seconds — at which point `audioPlayer.currentTime` was `endTime - 0.5`. For sections < 2s the threshold was never met → no pip credit, ever. Also, re-tapping the active block in the queue could credit a rep mid-play AND let re-runs credit again → `repsAttempted` exceeded `block.reps` ("8/5" pip math).
- **Rule:** On natural section completion (driven by the controller's own timer), credit the rep unconditionally via a separate `creditCurrentRep()` path that caps at `block.reps`. Only use the threshold-based path (`creditCurrentRepIfThresholdMet`) for manual nav (skip/select). When the engine has a pre-roll/fade offset, expose it as a `static let` so the controller can align its end-of-section timer (`sectionDuration + preRoll`).

## 2026-05-28 — Per-mix block config persistence + slide-to-skip rest

- **Category:** correction + best_practice
- **What happened:** Reps and rest length silently reset when switching to a different mix and returning, because `SavedMix` only persisted sections and `RootTabView.loadFromLibrary` rebuilt blocks via `addBlock(for: section)` (defaults). Sections persisted (already in `SavedMix.sections`) but block programming did not.
- **Rule:** When introducing per-mix programmable parameters (reps, rest, restartMode), persist them keyed by mix on the same `SavedMix` record, with a custom `init(from:)` that defaults missing keys to `[]` for backward-compat with older libraries. Sync via `.onChange(of: session.blocks)` in the builder.
- **Related UX:** "Skip rest" buttons in interval-trainer apps must NEVER skip past the warning beeps — that's the whole point of the warning. Use `skipBreakToCountdownTail()` to jump into the 5-second GET READY tail instead of straight to `.playing`. Replace any tap-to-skip with a slide-to-confirm so a stray tap can't cut rest entirely (`SlideToSkipRest` component, 85% triggerFraction).

## 2026-05-29 — No-simulator rule is for active development, NOT for QA

- **Category:** correction
- **What happened:** I asked the user how to run /qa given the project's "never use iOS Simulator" rule. They clarified the rule's actual scope.
- **Rule:** The "no simulator" rule applies to **active development** (coding/testing features I just built). For **QA runs**, always use the simulator (or a device if available AND not currently in use by the user). Right now the user is on the iPad — don't deploy QA builds to ianPad while they're using it; use the sim. Update `feedback_no_simulator` memory to reflect this scope.

## 2026-05-29 — Linear workspace hit free-issue quota; save_issue 6×failed

- **Category:** knowledge_gap
- **What happened:** Tried to file 6 QA findings via `mcp__claude_ai_Linear__save_issue` in one batch. All 6 returned `Usage limit exceeded - You've exceeded the free issue limit for this workspace.` Linear's Free plan caps total issues per workspace.
- **Rule:** Before batch-filing issues to Ianplus, check the workspace's quota. If quota is hit, save a paste-ready markdown file (one issue per H2 with title/body/labels/priority) next to the QA report so the user can paste manually when they get to it. Don't silently lose findings.
