# CheerPracticePlayer — App Store Screenshot Capture Spec

Consumed by `~/.config/appstore-auto/run.sh` (launchd `com.ianrichardson.appstore-auto`, Mon-Fri 5:32am PT).

## Goal
Produce iPhone 6.9" portrait screenshots for the App Store 1.0 listing.

## Required dimensions
| Device | Portrait |
|---|---|
| iPhone 6.9" (iPhone 16 Pro Max / 17 Pro Max) | 1320 × 2868 |

App is iPhone-portrait-only — no iPad, no Catalyst, no landscape.

## Output layout
Under `AppStoreScreenshots/auto/<YYYY-MM-DD>/`:
```
auto/
  <date>/
    iphone69/
      screenshot_01_home.png
      screenshot_02_builder.png
      screenshot_03_live_run.png
      screenshot_04_block_detail.png
      screenshot_05_mix_library.png
    NOTES.md
```

Do not commit. Do not upload to ASC. Ian reviews and uploads manually.

## Prep
1. `git fetch origin && git status --porcelain` — bail if dirty tracked files.
2. `xcrun simctl shutdown all`
3. Find iPhone 16 Pro Max or 17 Pro Max simulator UDID. Prefer Pro Max (6.9"). Fall back: 15 Pro Max (still 6.7" 1290×2796, log substitution in NOTES.md — Apple still accepts 6.7" assets but the listing will look better with 6.9").
4. Build:
   ```
   xcodebuild -project CheerPracticePlayer.xcodeproj -scheme CheerPracticePlayer \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
     -derivedDataPath /tmp/cpp-auto-build build
   ```

## Capture flow

1. **Boot** the simulator + `open -a Simulator`.
2. **Install** the freshly built app.
3. **Launch** `com.ianrichardson.CheerPracticePlayer`.
4. **Wait** 3s for app to render.
5. **Seed demo data — IMPORTANT.**
   - The Home tab + Live Run tab need a `PrototypeSession` with a real `ImportedMix`. The sample session in code points to `/tmp/blackout-worlds-mix.m4a` which doesn't exist, so live run controls will be in empty/disabled state.
   - **First run gap:** No demo audio file exists yet. Log to NOTES.md: "No demo .m4a — captured empty/initial states. Manual capture pass needed for fully-populated screens."
   - **Future:** Bundle a silent .m4a (3:00 duration) under `.appstore/demo.m4a`, copy it into the sim before launch via `xcrun simctl push booted ...` and have the app auto-import on first launch (requires app code change — defer to 1.1).

6. **Take screenshots** via `xcrun simctl io booted screenshot <path>`. Target shots — capture whatever the current app state allows:

   1. **screenshot_01_home.png** — Home tab. Empty-state acceptable for v1 (shows session summary card or onboarding).
   2. **screenshot_02_builder.png** — Builder tab. If no mix imported, shows import call-to-action; that's fine and demonstrates the feature.
   3. **screenshot_03_live_run.png** — Run tab. Will be in idle state without mix; capture anyway — shows the big-button UI.
   4. **screenshot_04_block_detail.png** — Builder tab, scroll to or tap on a block detail card to expose the reps/rest/lead-in steppers. If no blocks exist (no mix), skip and log gap.
   5. **screenshot_05_mix_library.png** — Builder → Library button or Mix Library view. Empty state acceptable.

7. **Verify dimensions** with `sips -g pixelWidth -g pixelHeight`. Reject + log any file not matching target.
8. **Shutdown** simulator.

## NOTES.md template
```
# CheerPracticePlayer auto-capture — <date>

Device used: iPhone 17 Pro Max (6.9" @ 1320x2868)
Build: <git short SHA> / project.yml MARKETING_VERSION 1.0 / CURRENT_PROJECT_VERSION <N>

## Captured
- screenshot_01_home.png — <state>
- ...

## Gaps / FAILED
- <e.g., screenshot_04 skipped: no blocks exist without a mix imported>
- Demo .m4a not bundled — listing screens will look empty until a mix is imported.

## Suggested next action
- [ ] Ian: import a real cheer mix into the sim and re-capture screens 4 + 5 manually, OR
- [ ] Build feature: auto-seed demo mix on first launch (1.1 candidate).
```

## Why this is sparse for v1
This is the first ship. The app has no demo-data system. Apple's spec only requires 1 screenshot minimum; 3-5 is enough for a coherent listing. Empty-state screenshots that show UI clearly + descriptive captions in App Store Connect = acceptable v1. Polish in 1.1.
