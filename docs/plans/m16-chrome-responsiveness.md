# Sidebar and zoom animation responsiveness (milestone 16)

How milestone 16 of the [v1 roadmap](../v1-roadmap.md) is built, the second responsiveness milestone. Builds on
[m15-canvas-responsiveness.md](m15-canvas-responsiveness.md), the sidebar from
[m14-paper-chrome.md](m14-paper-chrome.md) and the details-panel zoom from [m6-details-panel.md](m6-details-panel.md).

**Status:** shipped

## Goal

Afterwards typing in the details panel no longer rebuilds the sidebar on every key, the zoom to a region when the
panel opens and closes moves in step with the display, and a canvas reload of unchanged regions does almost no
work.

## Scope

**In:**

- **The sidebar follows Observation only.** `ScreenSidebar.body` stops reading `model.revision`. The project, its
  screens and the settings are `@Observable`, so the list redraws when a screen, the order, a variant group or a
  preset changes; region edits reach a card only through its thumbnail revision, as before.
- **The details-panel zoom runs on the display link.** `CanvasViewController.animateCamera` steps the camera from
  `NSView.displayLink(target:selector:)` (macOS 14) instead of a 120 Hz `Timer`, using each frame's
  `targetTimestamp`, so every step lands on a frame while the inspector slides in.
- **Region text compared in Swift.** `RegionLayers.update` compares the title and the untrimmed description with
  the strings it last gave the text layers, so an unchanged region costs no bridging back from `CATextLayer` and no
  trimming.

**Out:**

- Sidebar card shadows, the grid replicator and autosave on the main thread: measured on a Mac first.

## Done when

**Tests and CI:**

- [ ] Every existing sidebar, details-panel and canvas test passes unchanged.
- [ ] The printed "reload after an edit" and "reload after retitling one region" times are lower than
  milestone 15's (9.89 and 8.58 ms on CI).
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Typing a title on a project with many screens keeps up, and the sidebar still shows renames, new screens,
  reordering, viewport changes and thumbnail updates.
- [ ] Opening and closing a region in the details panel zooms smoothly, with no judder.
