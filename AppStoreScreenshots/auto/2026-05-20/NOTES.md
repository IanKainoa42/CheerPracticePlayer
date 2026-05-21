# CheerPracticePlayer auto-capture — 2026-05-20

Device used: iPhone 17 Pro Max (6.9" @ 1320×2868)
Build: a14c673 / project.yml MARKETING_VERSION 1.0 / CURRENT_PROJECT_VERSION 2
Capture method: manual run (interactive Claude Code session), peekaboo-driven tab taps
Working tree at capture: dirty (audio fade-in/out + SoundEffectsPlayer staged, not part of build) — user confirmed "audio is fine, get screenshots"

## Captured (all 1320×2868, App Store-ready)
- `iphone69/screenshot_01_home.png` — Dashboard tab, rich empty state: "Good Evening / Wednesday, May 20" greeting, My Team card ("No mix imported"), "Ready to build your practice?" onboarding card with 1-2-3 step pills (Import mix → Mark sections → Practice), About section explaining the app. Strongest of the three shots — actually communicates the product.
- `iphone69/screenshot_02_builder.png` — Build tab empty state: centered "IMPORT MIX" pill (the only CTA, per minimal-UI bias). Tab bar shows Build selected (yellow).
- `iphone69/screenshot_03_live_run.png` — Live tab empty state: music-note icon, "NO BLOCKS" headline, "Create at least one practice block in the Build tab to start a live session." Clear gate explanation.

## Gaps / FAILED
- `screenshot_04_block_detail.png` — not captured. Requires a real imported mix + at least one block. No demo .m4a bundled; the app has no first-launch seed for sample data. Spec defers populated-state capture to 1.1.
- `screenshot_05_mix_library.png` — same gap; Mix Library is empty until a mix is imported.

## Suggested next action
- [ ] Ian: review the three shots and upload to App Store Connect as the v1.0 listing assets (Apple minimum: 1 screenshot, so 3 is sufficient).
- [ ] Ian: complete the user-side ASC age rating + privacy questionnaire forms (separate from screenshots; still blocking submission).
- [ ] 1.1 backlog: bundle a silent demo .m4a + add a first-launch seed flag (`-CPPAppStoreDemo 1`) so the LaunchAgent can fully self-drive populated-state capture next time.

## Process notes (for next capture run)
- iPhone 17 Pro Max simulator UDID: CF6EB8B9-7790-4BCF-950A-E18BDA2857C0
- Simulator window position when capturing: (1062, 59) size (440, 1020). iOS content offset y ≈ 70 px below window top (title bar).
- Tab bar pill (window-relative): Dashboard (130, 968), Build (220, 968), Live (305, 968).
- After tab tap, wait ≥4s for transition animation to settle. A 2s settle caught the cross-fade mid-frame on the first attempt and produced ghost-overlapped shots.
- Build is the default landing tab on cold launch — capture Dashboard first via explicit tap.

Nothing committed. Nothing uploaded to ASC. Ian reviews and uploads manually.
