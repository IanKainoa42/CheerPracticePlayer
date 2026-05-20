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
