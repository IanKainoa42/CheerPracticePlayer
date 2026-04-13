# Learnings

## 2026-04-11 — Always use .buttonStyle(.borderless) for Buttons inside SwiftUI List rows

- **Category:** correction
- **What happened:** Shipped SectionEditorCard with Button views inside a List row without `.buttonStyle(.borderless)`. SwiftUI expanded the Delete button's hit area to the entire row, so tapping anywhere on the card triggered deletion.
- **Rule:** Always add `.buttonStyle(.borderless)` to every Button inside a SwiftUI List row. Without it, List expands button tap targets to the full row width.
