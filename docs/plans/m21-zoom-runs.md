# Zoom without hitches (milestone 21)

How milestone 21 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on the zoom runs and text settle from
[m15-canvas-responsiveness.md](m15-canvas-responsiveness.md), the details-panel camera animation from
[m16-chrome-responsiveness.md](m16-chrome-responsiveness.md), and the mounted regions from
[m20-visible-layout.md](m20-visible-layout.md). From the profile in `real-hardware-profile.md` in the project files
(items 1 and 2).

**Status:** shipped

## Goal

Afterwards a pinch is smooth from its first frame to well after its last, at any region count: no catch as the
fingers land and none as the titles sharpen afterwards. The details-panel zoom gets the same treatment.

Today a zoom run (changes less than 0.15 s apart) re-lays out every region's layers each frame with the text
clipped, and the first change of a run fits the text at once, because nothing tells the canvas a run has begun. When
the run ends, `settleText()` re-truncates every title in one go. Measured on screen at 500 regions, Release: 16-20 ms
for the first pinch frame, 6.2 ms per frame during the pinch, and about 38 ms for the settle, so each pinch drops a
frame as it starts and two or three as it ends. At 2,000 regions the first frame is 87-131 ms. Milestone 20 cuts all
of these by the share of regions off screen; this milestone takes the rest off the frame.

## Scope

**In:**

- **A zoom run is drawn with a transform.** While a run is under way, the region and overlay layers stay laid out
  for the zoom the run began at (the layout zoom), and `regionsLayer` and `overlayLayer` get a scale transform of
  current zoom ÷ layout zoom. A pinch frame then changes two transforms and positions. Text, borders and corners
  scale with the transform until the run settles.
- **Runs begin and end on the gesture's phases.** A magnify event with phase `.began` begins a run; `.ended` and
  `.cancelled` end it. The details-panel camera animation begins a run on its first frame and ends it on its last.
  Changes without a phase (a mouse with a smart-zoom tap, or a test) keep today's timing rule: one soon after
  another joins a run, and the run ends `textSettleDelay` after the last.
- **A run that strays far is rebased.** When the transform's scale leaves 0.5 to 2, the mounted regions are laid out
  at the current zoom with the text clipped (as a pinch frame is today) and the transform goes back to 1, so the
  picture never blurs badly. With milestone 20 this costs only what is mounted.
- **Ending a run in two parts.** On the frame the run ends, the mounted regions are laid out at the final zoom with
  their text clipped, and the transform is removed, so geometry is exact at once. Fitting the text (re-truncating
  titles and descriptions, which redraws them) then happens over the next frames on the view's display link, within
  a budget of 4 ms of work per frame, regions nearest the view's center first. A new run cancels the fitting left.
- **Zoom commands stay single steps.** ⌘+, ⌘− and Actual Size lay out at the new zoom and fit text at once, as
  today; with milestone 20 that is only the mounted regions. They do not begin a run.

**Out:**

- Animating the zoom commands: they stay instant steps.
- Changing how titles truncate or which titles hide at small sizes.
- Rasterizing regions during a pan or a zoom: the profile showed render-server time flat at 4 to 5 ms per frame at
  every region count, so it would not help.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Zoom run state | `InterfaceDescriber/CanvasView.swift` | milestone 20 |
| 2 | Transform during a run, rebase | `InterfaceDescriber/CanvasView.swift` | 1 |
| 3 | Phases and the details animation | `InterfaceDescriber/CanvasView.swift`, `CanvasViewController.swift` | 1 |
| 4 | Ending a run, text in batches | `InterfaceDescriber/CanvasView.swift`, `RegionLayers.swift` | 2 |
| 5 | Tests and timings | `InterfaceDescriberTests/CanvasPerformanceTests.swift`, `OnScreenPerformanceTests.swift` | 2, 3, 4 |

1. **Zoom run state.** `CanvasView` gains `layoutZoom` (the zoom the mounted layers are laid out for) and a
   `ZoomRun` state: idle, running (with its layout zoom), or fitting (a queue of regions whose text waits). Every
   layout call uses `layoutZoom` rather than `camera.zoom`; outside a run they are equal. `beginZoomRun()` and
   `endZoomRun()` are internal so the controller and tests can call them.
2. **Transform during a run, rebase.** During a run a camera change sets the scale transform on `regionsLayer` and
   `overlayLayer` and the positions, and lays nothing out. Regions that mount mid-run (milestone 20) are laid out at
   `layoutZoom` so they match the others under the transform. When the scale leaves 0.5 to 2, the run rebases: lay
   out the mounted regions at the current zoom with `fitsText: false`, set `layoutZoom` to it, reset the transform.
   The sheet (`boundsLayer`) and the grid keep laying out for the real zoom each frame, as they are one layer each.
3. **Phases and the details animation.** `magnify(with:)` calls `beginZoomRun()` on `.began` and `endZoomRun()` on
   `.ended` or `.cancelled`. `CanvasViewController.animateCamera` begins a run before its first frame and ends it in
   the step that reaches `t == 1`, before the completion runs. The time-based rule in `zoomChanged()` stays for
   changes outside an explicit run, and an explicit run ignores it.
4. **Ending a run, text in batches.** `endZoomRun()` lays out the mounted regions at the final zoom with
   `fitsText: false`, resets the transform, then queues the regions whose text is not fitted, sorted by distance from
   the view's center. A display-link callback fits queued regions until 4 ms have passed, then waits for the next
   frame; regions that unmount drop out of the queue and fit when they mount again. `settleText()` (used by tests and
   by a zoom command) still fits everything at once. `isTextSettled` is true once the queue is empty.
5. **Tests and timings.** Tests: during a run, a camera change leaves every mounted box's bounds unchanged and sets
   the transform's scale to the zoom ratio; a run zoomed past 2× rebases (layers resized, transform back to 1); after
   `endZoomRun()` the boxes have their final frames at once and the titles fit once the queue drains, matching a fresh
   canvas at the same zoom (as `testTitlesAreFittedOnceAZoomRunSettles` checks today); a phase-less run still settles
   by time. `OnScreenPerformanceTests` adds a pinch with begin and end at 500 and 2,000 regions, timing the first
   frame, the median frame, and the worst frame while the text fits.

## Done when

**Tests and CI:**

- [ ] The tests in step 5 pass, and `testTitlesAreFittedOnceAZoomRunSettles` and every other canvas test pass.
- [ ] `OnScreenPerformanceTests` prints the pinch timings; the PR reports them against milestone 20's numbers.
- [ ] `scripts/check.sh` passes (the PR says which stages ran).

**On the Mac (MacBook Air M1, Release):**

- [ ] On the 500-region project, a pinch at 100 % and a pinch fitted never miss a frame, from the first frame to the
  last fitted title (the PR reports the worst frame).
- [ ] On the 2,000-region project, a pinch frame is under 3 ms and no frame while the text fits is over 16.7 ms.
- [ ] Titles look slightly scaled during a pinch and sharp within a few frames after it; nothing jumps when the run
  ends or rebases.
- [ ] The details-panel zoom in and out is smooth on the 500-region project, and the title of the opened region is
  sharp when the panel settles.
- [ ] ⌘+, ⌘− and ⌘0 still zoom in one step with sharp titles.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| How far can a run scale before it rebases? | 0.5× to 2× of the layout zoom. | |
| Text-fitting budget per frame? | 4 ms, about half a frame at 120 Hz. | |
