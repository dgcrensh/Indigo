# A grid that pans without redrawing (milestone 19)

How milestone 19 of the [v1 roadmap](../v1-roadmap.md) is built, a canvas responsiveness milestone. Builds on the grid
from [m13-paper-look.md](m13-paper-look.md) and the pan from [m15-canvas-responsiveness.md](m15-canvas-responsiveness.md).
Item 2 of `performance/pan-stutter-recommendations.md` in the project files; the other items there wait for a profile
on a Mac.

**Status:** shipped

## Goal

Afterwards panning with snapping on moves one strip of dots repeated down the view, instead of thousands of separate
dots, so the grid costs about the same to draw however dense it is.

The grid was a `CAReplicatorLayer` of one dot layer repeated along a row, and the row repeated down the view. With the
default 8-point grid and the 10-point minimum spacing, a 1440 × 900 canvas drew about 5,000 dot instances at 100 %
and up to about 13,000 zoomed out, each composited on every frame of a pan, and every pan step recounted them.

## Scope

**In:**

- **`GridTiling` in the core.** For a grid size, camera, view size and minimum spacing: the drawn step, the spacing in
  view points, the view point of the last line at or before the view's top-left corner, and how many lines reach past
  the far edges. The counts depend only on the spacing and the view's size, so a pan changes only the origin.
- **The canvas draws one row image.** One image of a row of dots, drawn with Core Graphics at the backing scale, as
  the contents of one layer, repeated down the view by a replicator. A pan only moves the replicator. The image is
  drawn again only when the spacing, the column count, the dot color or the scale changes. The grid is clipped to
  the view.

**Out:**

- Pacing pans to the display link, flattening regions during a pan, shadow paths on the floating chrome, and autosave
  during a gesture: each waits for a profile on a Mac (`pan-stutter-recommendations.md` items 1 and 3 to 6).
- Any change to the grid's look: dot size, spacing rules and color stay as they are.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Grid tiling | `Layout/CanvasLayout.swift`, `Tests/.../CanvasLayoutTests.swift` | none |
| 2 | Row image on the canvas | `InterfaceDescriber/CanvasView.swift`, `InterfaceDescriberTests/CanvasPerformanceTests.swift` | 1 |

1. **Grid tiling.** `GridTiling.init?(grid:camera:viewSize:minimumSpacing:)`, nil with no grid or an empty view.
   Tests: the origin is the last line before the corner, a line on the edge sits at 0, and panning keeps the counts
   and spacing while the origin stays in `(-spacing, 0]`.
2. **Row image on the canvas.** `layoutGrid()` takes the tiling, redraws the row image only when its key changes, and
   positions the rows at the origin. `showsGridDots` and `gridDotCount` keep working for tests. A test pans and checks
   the row image is the same object and the dot count is unchanged, and that a zoom draws a new image.

## Done when

**Tests and CI:**

- [ ] `GridTiling` is covered in `CanvasLayoutTests`.
- [ ] `testPanningMovesTheGridWithoutDrawingItAgain` passes, and the existing grid tests pass unchanged.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] The grid looks as before at 25 %, 100 % and 400 %, in light and dark, and on a 1× and a 2× display.
- [ ] The dots stay on the grid lines while panning and pinching, and regions still snap onto them.
- [ ] Panning with snapping on is as smooth as with it off (press S to compare).
