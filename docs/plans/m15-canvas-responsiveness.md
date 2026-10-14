# Canvas responsiveness: edits and pinch (milestone 15)

How milestone 15 of the [v1 roadmap](../v1-roadmap.md) is built, the first of the responsiveness milestones that
follow the Paper studio. Builds on the canvas from [m4-canvas-rendering.md](m4-canvas-rendering.md) and the
500-region timings from [m12-hardening.md](m12-hardening.md).

**Status:** shipped

## Goal

Afterwards an edit costs the canvas about what it changed, so typing in the details panel, undo, nudge and paste no
longer redraw every region, and a pinch no longer re-truncates every visible title on every frame.

The CI timings this starts from (500 regions, macOS 14 runner): reload after an edit 12.2 ms, pinch at about
100 % 12.1 ms per frame. A frame at 120 Hz is 8.3 ms.

## Scope

**In:**

- **Reload skips unchanged regions.** `RegionLayers` remembers whether anything its layout depends on changed (frame,
  parts outside the bounds, clip, scroll indicators, title, whether it has a description or links, whether the
  description shows) and the zoom of its last layout. `layoutIfNeeded(zoom:)` lays out only when one of those
  changed. `CanvasView.reload()` applies colors only to new layers (or after the backing scale changed; an
  appearance change already re-applies them to every layer), and sets `regionsLayer.sublayers` only when the
  z-order changed, since setting it removes and re-adds every box.
- **Text settles after a zoom run.** The title and description sit in a clip layer inside the box. A zoom change
  that comes within `CanvasView.textSettleDelay` (0.15 s) of the previous one lays regions out with `fitsText`
  false: text that is showing keeps its size and is clipped, so nothing redraws. A timer fits the text once the
  zoom has stayed put for the delay, and the end of a pinch fits it at once. A single zoom change (Cmd +, Cmd −,
  Cmd 0) fits it immediately. The details-panel zoom animation takes the same path.
- **Timings.** `CanvasPerformanceTests` adds "reload after retitling one region" (under 16 ms) and redraws the
  whole layer tree when timing, since the text now sits one level deeper.
- **The subtitle test waits for the change** rather than a fixed 50 ms, which a slow runner missed on `main`.

**Out:**

- The sidebar redrawing every card on every edit, and driving the details-panel zoom from the display link: the
  next responsiveness plan.
- Sidebar card shadows, the grid replicator and autosave cost: measured before anything is changed.

## Done when

**Tests and CI:**

- [ ] `testTitlesAreFittedOnceAZoomRunSettles`: a run of zoom changes leaves text unfitted, it is fitted once the
  zoom stays put, and the fitted titles match a fresh canvas at the same zoom.
- [ ] "reload after retitling one region" is under 16 ms on CI, and the printed pinch time at about 100 % is lower
  than 12.1 ms.
- [ ] Every existing canvas test passes unchanged.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Typing a title in the details panel on the 500-region stress project keeps up with the keys.
- [ ] Pinching at about 100 % is smooth; titles clip while the fingers move and gain their ellipsis when they lift.
- [ ] Cmd + and Cmd − still show correctly truncated titles straight away.
