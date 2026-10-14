# A sidebar that redraws only what changed (milestone 24)

How milestone 24 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on the sidebar cards and thumbnails from
[m14-paper-chrome.md](m14-paper-chrome.md) and the observed sidebar from
[m16-chrome-responsiveness.md](m16-chrome-responsiveness.md). From the profile in `real-hardware-profile.md` in the
project files (items 7 and 8). Independent of milestones 20 to 23.

**Status:** draft

## Goal

Afterwards scrolling a long sidebar never drops a frame, and switching screens redraws two cards, not all of them.

Measured on the Mac (MacBook Air M1, Release) with 40 screens of 300 regions and the sidebar open:

- **Scrolling the sidebar:** 4.7 ms median, but 18-22 ms when new cards scroll in (8 dropped frames in 480). Each
  card's thumbnail recomputes `ScreenThumbnail.rects` in its body and converts each family's `PaperColor` to a
  `CGColor` per rectangle while drawing. Render-server time stays at 4.2 ms median, so the card shadows are not the
  cause.
- **Switching screens:** 13 ms median, 46 ms worst. About a third is the sidebar re-evaluating every card, because
  each card reads `model.activeScreenID` to decide its accent ring. (Another third is the canvas building the new
  screen's layers, which milestone 20 cuts.)

## Scope

**In:**

- **One view per card.** The card becomes its own `ScreenCard` view taking the screen, whether it is active, the
  renaming state and its thumbnail revision as inputs. The list passes `isActive` down, so a screen switch changes
  the inputs of two cards and SwiftUI skips the rest.
- **Thumbnails computed once per revision.** The thumbnail's rectangles are computed when its revision changes, not
  in every body: `ThumbnailRevision` holds the last `ScreenThumbnail` it was computed for, keyed by revision value,
  size and color scheme. A card that scrolls back into view reuses it.
- **Colors resolved once per draw.** The thumbnail resolves the palette's fill and border `Color` for each kind
  family once per draw, then fills every rectangle with them.

**Out:**

- The card shadow: the profile cleared it. It stays as designed.
- Replacing `List` with a `LazyVStack` or an `NSTableView`: only if the three changes above leave scroll spikes over a
  frame.
- The canvas part of a screen switch: milestone 20.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | `ScreenCard` view | `InterfaceDescriber/ScreenSidebar.swift` | none |
| 2 | Cached thumbnail rects and colors | `InterfaceDescriber/ScreenThumbnailView.swift`, `DocumentModel.swift` | none |
| 3 | Timings | `InterfaceDescriberTests/OnScreenPerformanceTests.swift` or `ScreenManagementTests.swift` | 1, 2 |

1. **`ScreenCard` view.** Move `screenCard(_:)` into `struct ScreenCard: View` with `screen`, `isActive`,
   `isRenaming`, a binding for the draft name, the revision, the controller and the user presets as inputs. Its tap,
   context menu, rename field and accessibility traits behave exactly as today. The sidebar body reads
   `activeScreenID` once and passes `isActive` to each card.
2. **Cached thumbnail rects and colors.** `ThumbnailRevision` gains a cached `ScreenThumbnail` with the key it was
   computed for; `ScreenThumbnailView` asks it for the rects and recomputes only on a key change. Inside the
   `Canvas`, a dictionary from family to resolved fill and border is built once per draw.
3. **Timings.** Time switching screens and scrolling the sidebar on a shown window holding the 40 × 300 project, and
   print them. A test checks that after switching screens only the previously active and newly active cards' bodies
   ran (a debug-only body counter on `ScreenCard`), and that a thumbnail's rects are computed once across two
   redraws at the same revision.

## Done when

**Tests and CI:**

- [ ] The body-count and thumbnail-cache tests in step 3 pass, and every existing `ScreenManagementTests` and
  `PaperLookTests` test passes.
- [ ] The timings print; the PR reports them against the numbers above.
- [ ] `scripts/check.sh` passes (the PR says which stages ran).

**On the Mac (MacBook Air M1, Release):**

- [ ] Scrolling the sidebar of the 40 × 300 project top to bottom and back drops no frames.
- [ ] Switching screens by clicking cards takes under 8 ms with the sidebar open (with milestone 20 in).
- [ ] Cards look exactly as before in light and dark, the accent ring follows the active screen, and renaming,
  reordering by drag and the context menu still work.
- [ ] Editing regions updates that screen's thumbnail within the throttle, and only that one.
