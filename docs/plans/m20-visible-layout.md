# Lay out only what is on screen (milestone 20)

How milestone 20 of the [v1 roadmap](../v1-roadmap.md) is built, the first of the measured responsiveness milestones.
Builds on the region layers from [m4-canvas-rendering.md](m4-canvas-rendering.md) and the skipped reloads and zoom
runs from [m15-canvas-responsiveness.md](m15-canvas-responsiveness.md). From the profile in `real-hardware-profile.md`
in the project files (items 1, 2, 4 and 7), measured on a MacBook Air M1 at 60 Hz.

**Status:** shipped

## Goal

Afterwards the canvas does work in proportion to the regions on screen, not the regions on the screen file: zooming,
panning, reloading after an edit and switching screens cost about the same on a 5,000-region screen as on a
500-region one when you are zoomed in.

Today every region has its layers in the tree and every zoom change lays them all out. Core Animation then commits
every changed layer, and walks every layer even on a pan that moves three. Measured on screen, Release:

| Per action | 500 regions | 2,000 | 5,000 |
| --- | ---: | ---: | ---: |
| Zoom command at 100 % (first pinch frame is the same work) | 16-20 ms | 87-131 ms | ~200 ms |
| Pinch frame at 100 % (median) | 6.2 ms | 11.4 ms | 33.6 ms |
| Pan frame | 0.9 ms | 3.3 ms | 7.4 ms |

About 60 % of the 5,000-region pan step is `canvasScrollTarget(at:)` building a fresh `ScrollLayout` and
`RegionIndex`, which runs on every mouse-wheel step and on the first event of every trackpad scroll.

The existing `CanvasPerformanceTests` never commit to a window, so they time a pinch frame at 1.2 ms where the screen
sees 6.2 ms. This milestone adds on-screen timings first, so its own before and after, and every later milestone's,
show up in CI.

## Scope

**In:**

- **On-screen canvas timings.** A test case that opens the stress document's window on screen and times each step
  including `CATransaction.flush()`, so the Core Animation commit is part of the number. It runs at 500, 2,000 and
  5,000 regions and prints the numbers. Its assertions are loose, as CI runners are slow.
- **Covered rect.** The canvas keeps a covered rect in screen points: the visible rect plus half a view on every side.
  Regions whose drawn frame (or, for a clipped region, its clip) intersect it are mounted: their box is in
  `regionsLayer` and laid out for the zoom. The rest are unmounted: their box is out of the tree and their layout
  waits. The covered rect is computed again only when the visible rect leaves it or the zoom changes, so most pan
  frames change nothing but three positions.
- **Layers made on first mount.** `RegionLayers` are made the first time a region is mounted and kept after that, so
  showing a screen makes layers only for what it shows. Selection, description and scroll state are applied when a
  region mounts.
- **Mounted boxes in z-order.** On a mount change, the mounted boxes are set as `regionsLayer`'s sublayers in draw
  order, only when the list changed (as `reload()` already does).
- **The scroll target reuses the canvas's layout.** `canvasScrollTarget(at:)` hit-tests against the `ScrollLayout`
  the canvas already holds for the shown screen and scroll offsets, instead of building one, and the selection it
  needs is pruned once per selection change, not per event.

**Out:**

- Drawing a zoom run with a transform and fitting text over several frames: milestone 21, which builds on this.
- Any change to what a region looks like, how it is hit-tested, or how the PNG export draws
  (`ScreenImageRenderer` makes its own `RegionLayers` and keeps doing so).
- Unmounting regions that are selected or being dragged: a gesture's regions stay mounted until it ends, so the
  drag preview never loses a layer.
- Destroying layers of regions that scroll away: they are kept, so coming back costs no rebuild.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | On-screen timings | `InterfaceDescriberTests/OnScreenPerformanceTests.swift` | none |
| 2 | Covered rect in the core | `Layout/CanvasLayout.swift`, `Tests/.../CanvasLayoutTests.swift` | none |
| 3 | Mount and unmount on the canvas | `InterfaceDescriber/CanvasView.swift`, `RegionLayers.swift` | 2 |
| 4 | Scroll target from the canvas's layout | `InterfaceDescriber/CanvasViewController.swift`, `CanvasView.swift` | none |
| 5 | Tests on the culled canvas | `InterfaceDescriberTests/…` | 3 |

1. **On-screen timings.** `OnScreenPerformanceTests` opens a `Document` holding `Project.stressTest(regionCount:)` in
   a 1440 × 900 window that is shown, and times, per step and including `CATransaction.flush()`: a pan at 100 %, a
   pinch run at 100 % and fitted, one zoom command, a reload after retitling one region, nudging one region and
   nudging all, and showing the screen in a new window. It prints one line per timing at 500, 2,000 and 5,000
   regions, and asserts only the 500-region pan, pinch and nudge (under 16 ms each, loose for CI). It lands first
   and runs before step 3 so the PR can report the before numbers from the same test. The scratch harness from the
   profile (`profiling-probe-tests.swift` in the project files) is the starting point; the display-link driving stays
   out, since CI runners may not tick it.
2. **Covered rect in the core.** `CanvasCoverage` in `CanvasLayout.swift`: for a camera, view size and margin
   fraction, the visible rect and the covered rect in screen points, and `needsRecompute(visible:)` that is true when
   the visible rect is no longer inside the covered one. `ScrollLayout.regions(intersecting:)` returns the draw-order
   positions whose drawn frame, cut to its clip, intersects a rect; a region entirely clipped away never intersects.
   Tests: the covered rect contains the visible rect with the margin, a pan inside the margin needs no recompute and
   one past it does, a zoom always does, and `regions(intersecting:)` on the stress screen returns the expected
   containers, rows and items for a rect over the first container, including a scrolled-out child that is excluded.
3. **Mount and unmount on the canvas.** `CanvasView` keeps `coverage` and a `mounted: Set<RegionID>`. `reload()`
   still updates every region's model state (title, kind, frame) on its `RegionLayers` when it has one, but lays out
   and mounts only covered regions, plus the selection and any previewed regions. A camera change recomputes the
   coverage when `needsRecompute` says so (always on a zoom); newly covered regions are made if needed, laid out with
   `layoutIfNeeded(zoom:)` and mounted; uncovered ones are removed from the tree. `layoutContent`, `settleText`,
   `applyScroll` and `visibleDescriptions` touch only mounted regions; unmounted ones keep `needsLayout` set so they
   lay out when they mount. A view resize recomputes the coverage.
4. **Scroll target from the canvas's layout.** `CanvasView` exposes its `scrollLayout` (already kept for the shown
   screen and offsets); `canvasScrollTarget(at:)` uses it, and falls back to building one only when the canvas shows
   no screen. `currentSelection` keeps a pruned copy keyed by the model's selection and revision, so it is pruned once
   per change. The trackpad route is still chosen once per gesture.
5. **Tests on the culled canvas.** Accessors for tests (`drawnFrame(of:)`, `isClippedAway`, `fillColor(of:)`,
   `cornerRadius(of:)`, `scrollIndicatorCount(of:)`, the `…LayerIDs` sets, `isTextSettled`) answer for every region
   whether or not it is mounted: they make and lay out the region's layers on demand without mounting them.
   `regionLayerCount` keeps meaning "regions on the screen with layers or due them"; a new `mountedRegionCount` is
   what is in the tree. New tests: on the 500-region screen at 100 % only the regions in the covered rect are mounted;
   panning down a container's height mounts the next row of containers and unmounts the ones that left; a zoom out
   to fit mounts everything; a selected region scrolled far away stays mounted while selected; z-order of mounted
   boxes matches draw order after mounts and unmounts. Every existing canvas test passes.

## Done when

**Tests and CI:**

- [ ] `CanvasCoverage` and `ScrollLayout.regions(intersecting:)` are covered in `CanvasLayoutTests`.
- [ ] The mount tests in step 5 pass, and every existing test in `InterfaceDescriberTests` passes unchanged except
  where step 5 names a changed accessor.
- [ ] `OnScreenPerformanceTests` prints before and after numbers; the PR reports them next to the table above.
- [ ] `scripts/check.sh` passes (the PR says which stages ran).

**On the Mac (MacBook Air M1, Release):**

- [ ] On the 5,000-region stress project at 100 %, a pan frame is under 2 ms and a zoom command under 12 ms.
- [ ] On the 500-region project at 100 %, a zoom command is under 8 ms and a pinch frame under 3 ms.
- [ ] Panning quickly across the whole 5,000-region screen never shows an empty spot where a region should be.
- [ ] Selection, descriptions (`D`, `Shift-D`), scrolling regions, link dots and the outside-the-frame tint look as
  before on regions that scroll into view.
- [ ] Dragging a selection far across the screen keeps every dragged region drawn.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| How much margin around the view? | Half a view on every side: a pan of up to half a screen changes no mounts. | |
| Make layers for every region up front, or on first mount? | On first mount, so showing a large screen costs what is visible. | |
