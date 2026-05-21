# CheerPracticePlayer auto-capture — 2026-05-20

Device used: iPhone 17 Pro Max (6.9" @ 1320×2868)
Build: HEAD (post `a14c673`, post Library refactor) / project.yml MARKETING_VERSION 1.0 / CURRENT_PROJECT_VERSION 2
Capture method: manual run (interactive Claude Code session), peekaboo-driven tab taps
Working tree at capture: dirty (Library refactor + new HomeView + RootTabView + PracticeBuilderView changes — not committed yet)

## Re-shoot context
First pass at 17:55 captured the OLD Dashboard greeting as shot 01. After user feedback ("Dashboard should be the library tab"), HomeView was refactored into a library-first design and shots were re-taken at 18:55 against the new build. Old `screenshot_01_home.png` was removed; replaced by `screenshot_01_library.png`.

## Captured (all 1320×2868, App Store-ready)
- `iphone69/screenshot_01_library.png` — **Library tab empty state.** Large "Library" navigation title, centered tray icon, "No Saved Mixes" headline, "Import a mix and save it here for one-tap reuse." subtitle, yellow "IMPORT MIX" pill CTA. Tab bar: Library (selected/yellow), Build, Live.
- `iphone69/screenshot_02_builder.png` — Build tab empty state: centered yellow "IMPORT MIX" pill. Tab bar shows Build selected.
- `iphone69/screenshot_03_live_run.png` — Live tab empty state: music-note icon, "NO BLOCKS" headline, "Create at least one practice block in the Build tab to start a live session." Tab bar shows Live selected.

## Gaps / FAILED
- Populated-state shots (mix loaded with sections + blocks, Library row stats visible, block detail editor) — not captured. Requires real imported audio and section marking. No demo `.m4a` bundled; no first-launch seed flag. Spec defers to 1.1.

## Suggested next action
- [ ] Ian: review the three shots; upload to App Store Connect as the v1.0 listing assets.
- [ ] Ian: complete ASC age rating + privacy questionnaire (user-side; still blocking submission).
- [ ] Commit the Library refactor + new HomeView before any release tag.
- [ ] 1.1 backlog: bundle silent demo `.m4a` + add `-CPPAppStoreDemo 1` first-launch seed flag for fully-populated captures (Library row with stats, block detail editor, live mid-run).

## Process notes (for next capture run)
- iPhone 17 Pro Max simulator UDID: CF6EB8B9-7790-4BCF-950A-E18BDA2857C0
- Simulator window position when capturing: ~(1062, 59) size (440, 1020). iOS content offset y ≈ 70 px below window top (title bar).
- Tab bar pill (window-relative): **Library** (130, 968), **Build** (220, 968), **Live** (305, 968) — labels renamed but positions identical to pre-refactor.
- After tab tap, wait ≥4s for transition animation to settle. A 2s settle catches the cross-fade mid-frame and produces ghost-overlapped shots.
- Fresh install cold-start now lands on **Build** when library is empty (RootTabView.init checks `mixLibrary.mixes.isEmpty`). Tap Library tab explicitly to capture its empty state.
- For a clean run, uninstall the app first (`xcrun simctl uninstall <UDID> com.ianrichardson.CheerPracticePlayer`) so no prior saved mixes leak in.

Nothing committed. Nothing uploaded to ASC. Ian reviews and uploads manually.
