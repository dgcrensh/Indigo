# Scrolling (milestone 9)

How milestone 9 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on
[m5-tools-gestures.md](m5-tools-gestures.md) and [m6-details-panel.md](m6-details-panel.md), and uses the sidebar
from [m8-screens-links.md](m8-screens-links.md).

**Status:** shipped

## Goal

Afterwards a scrollable region works on the canvas as spec Sections 3.4, 4 and 5 describe. Its children are drawn at
its scroll position and clipped to its frame, with a scroll indicator showing where it is and a dashed outline of
the whole content area while it is selected. Two-finger scroll over a selected scrollable region scrolls it instead
of panning, so children can be drawn, moved and resized in content that was hidden below or beside the frame. Each
region's scroll position is kept in `.editor-state.json`. A screen's scrolling is set in the sidebar.

## Scope

**In:**

- Scroll positions in the core: each scrolling region's offset, clamped to its content and limited to its axis; where
  that draws every region ("drawn" frames: the file's frame moved by the offsets of the scrolling regions around
  it, spec 3.4), and the rectangle it is clipped to (the frames of those regions). A region whose clip leaves
  nothing is hidden.
- Hit testing, the marquee and the handles in drawn frames, so a click hits what is drawn and never a clipped-out
  region.
- The parenting rule at a scroll position. A gesture gives a drawn frame; a candidate parent's content area is
  compared where it is drawn, at its scroll position, and the region's frame in the file is the drawn frame moved
  by the chosen parent's offsets. A scrolling region is a candidate only when the frame overlaps the region's
  frame as drawn: hidden content can only receive a region after scrolling it into view (spec 5, "This is how users
  place children in content that is outside the visible frame"). Without scroll positions, drawn frames are the
  file's frames, so the rule is the spec's rule with that one addition.
- A region that was entirely hidden before a move (a nudge after Select All, say) keeps its scrolling parent while
  the parent's content area still holds it, instead of leaving it because it isn't in view.
- `CreateRegion`, `MoveRegions`, `ResizeRegion` and `PasteRegions` take the screen's scroll positions and treat
  their frames and deltas as drawn. Copy and Duplicate paste beside what is drawn.
- Changing a region's scrolling (turning it off, or shrinking the content) re-applies the parenting rule to children
  that no longer fit its content area (left out of milestone 6). The details panel's undo step puts them back.
- Scroll indicators: where the frame sits in the content along each axis that scrolls, as fractions, from the core;
  drawn as thin bars inside the region.
- The canvas: regions drawn at their drawn frames and clipped by a mask; the parts outside the screen's canvas bounds
  marked at drawn frames; scroll indicators; a dashed outline of each selected scrolling region's content area at
  its scroll position. While a move is previewed, the moved regions aren't clipped by regions outside the move, so
  a region dragged out of scrolled content stays visible.
- Two-finger scroll (and the mouse wheel) over a selected scrollable region scrolls it; anywhere else it pans. A
  trackpad gesture keeps the target it started with, including its momentum. Offsets are saved in the screen's
  editor state like zoom: not an edit, not undoable, written on the next save.
- Zoom-to-fit for the details panel, the link menu anchor, and the cursor over handles use drawn frames.
- A screen's scrolling in the sidebar under the viewport: a Scrolls checkbox (vertical, content as wide as the
  viewport and twice as tall) and, when on, the axis and content width and height, never smaller than the viewport.
  Each change is one "Change Scrolling" step.

**Out:**

- Scrolling the screen itself on the canvas. The canvas draws a scrolling screen's whole content area (spec 4).
- Scroll positions in the file or in exports. They are editor state (spec 3.1); exports use the file's frames
  (milestone 11).
- Undo for scroll positions. Like zoom and pan, they are not edits.
- Re-parenting regions outside a region when its content grows. The rule runs after create, move and resize (spec
  5), and a scroll change only re-places the region's own children that no longer fit.
- Rubber-banding, scroll bars that can be dragged, and animated scrolling.
- Settings for scroll defaults (milestone 10).

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Scroll layout | `…/Layout/ScrollLayout.swift`, `…/Layout/CanvasLayout.swift` | none |
| 2 | Parenting at a scroll position | `…/Layout/Parenting.swift` | 1 |
| 3 | Commands, the clipboard and the region editor | `…/Commands/RegionCommands.swift`, `…/Editing/RegionClipboard.swift`, `…/Editing/RegionEditor.swift` | 2 |
| 4 | Gestures in drawn frames | `…/Editing/CanvasGesture.swift` | 1, 3 |
| 5 | Drawing scrolled content | `InterfaceDescriber/CanvasView.swift`, `InterfaceDescriber/RegionLayers.swift`, `InterfaceDescriber/CanvasColors.swift` | 1 |
| 6 | Scrolling in a region, and commands with scroll positions | `InterfaceDescriber/CanvasViewController.swift`, `InterfaceDescriber/DetailsPanelController.swift` | 3, 4, 5 |
| 7 | A screen's scrolling in the sidebar | `InterfaceDescriber/ScreenController.swift`, `InterfaceDescriber/ScreenSidebar.swift` | none |

1. **Scroll layout.** `ScrollLayout(screen:offsets:)` walks the tree once. `offset(of:)` is the saved offset clamped
   to `0…content − frame` on each axis the region scrolls along, zero otherwise. `drawnFrame(of:)`, `clip(of:)`,
   `visibleFrame(of:)` (nil when hidden), `drawnContentArea(of:)`, `contentShift(of:)` (what a child's frame is
   moved by), `region(at:)` and `regions(touching:)` (topmost and touched by visible frames),
   `scrollTarget(at:among:)` (the topmost selected region that can scroll and is visible under the point),
   `scrolled(_:byDX:dy:)` (a new clamped offset), `indicators(of:)`, and `drawn(_:previewing:)` (frame and clip of a
   region during a preview). `Frame.intersection(_:)`. Tests: clamping per axis, nested offsets add up, clips
   intersect and hide, hit testing skips clipped-out regions and finds scrolled ones where they are drawn, the
   scroll target, indicator fractions, preview clips.
2. **Parenting.** `Parenting.placement(forDrawn:excluding:in:offsets:keeping:)` returns the parent and the frame in
   the file. `parent(for:excluding:in:)` keeps its meaning with no offsets. `place` and `reparentAfterChange` take
   the offsets and move the subtree when its frame in the file changes. Tests: the old below-the-fold test becomes
   "below the frame isn't a child until scrolled into view"; drawn into scrolled content; straddling the frame's
   edge; a hidden region kept on a nudge.
3. **Commands.** The four commands gain `scrollOffsets` (default empty, which changes nothing for existing callers).
   `RegionCommands.setScroll` becomes `SetRegionScroll`, which re-places children that no longer fit and undoes to
   the same layout. `RegionEditor.setScroll(_:scrollOffsets:)`, and its restore puts the layout back with the scroll.
   `RegionClipboard.paste(onto:in:grid:actionName:scrollOffsets:)` pastes copies of regions on the same screen at
   their drawn frames. Tests: moving a child out of and into scrolled content lands where it was dropped; resizing
   in scrolled content; duplicate in scrolled content stays inside beside the original; turning scrolling off
   re-places children and undo gives the same bytes; a details panel session that changes scrolling undoes to the
   same bytes.
4. **Gestures.** `GestureContext.scrollOffsets`. Presses, the marquee and the handles use the layout; previews are
   drawn frames; released commands carry the offsets. Tests: a drag in scrolled content previews drawn frames and
   its command lands there; a click on a clipped-out spot hits the region behind; drawing in scrolled content.
5. **Drawing.** `CanvasView.scrollOffsets`; a cached drawn frame and clip per region, so a scroll updates only the
   layers that moved. `RegionLayers.setClip(_:)` (a mask, or hidden) and `setScrollIndicators(_:)`. A dashed content
   outline in the overlay for selected scrolling regions.
6. **Scrolling.** `CanvasInteraction.canvasScrollTarget(at:)` and `canvasScroll(_:byViewDX:dy:)`. The controller
   keeps fractional deltas per region, writes offsets to the screen's editor state (dropping zero ones) and gives the
   canvas the new offsets. Gestures, nudges, paste and the details panel get the screen's offsets. App tests:
   scrolling a selected region scrolls it and not the camera; an unselected one pans; drawing after scrolling makes a
   child in hidden content; a scrolled-out child's layer is hidden; the offset is in the editor state.
7. **Screen scrolling.** `ScreenController.setScrolls(_:of:)` and `setScroll(axis:width:height:of:)`, one "Change
   Scrolling" step each, and the sidebar controls. App tests: turning it on sets the default and undoes in one step;
   content smaller than the viewport is raised.

## Done when

**Tests and CI:**

- [ ] (Core) Offsets clamp to the content and the axis, nest, and clip; hidden regions can't be hit or touched.
- [ ] (Core) The scroll target is the topmost selected scrollable region under the point.
- [ ] (Core) Drawing into scrolled content makes a child whose file frame is moved by the offset; drawing below an
  unscrolled region's frame doesn't make a child.
- [ ] (Core) Moving a region out of and into scrolled content lands where it is dropped; nudging a hidden region keeps
  its parent.
- [ ] (Core) Turning scrolling off re-places children outside the frame, and undo gives the same bytes.
- [ ] (Core) A gesture in scrolled content previews and commits at drawn frames.
- [ ] (App) Two-finger scroll over a selected scrollable region scrolls it and saves the offset; elsewhere it pans.
- [ ] (App) Scrolled children are drawn moved and clipped; a child scrolled out of view is hidden.
- [ ] (App) A screen's scrolling set in the sidebar is one undo step.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Draw a region, turn on Scrolling in the panel, and select it: a dashed outline shows content twice as tall, and
  a scroll indicator shows at the right edge.
- [ ] Two-finger scroll over it: its content scrolls and the canvas stays still. Draw a child in the content that
  was hidden, then scroll back: the child is clipped away.
- [ ] Drag a child out of the scrolled region onto the screen: it lands where it is dropped, at the top level.
- [ ] Two-finger scroll over the region while it isn't selected: the canvas pans.
- [ ] Close and reopen the document: the region is scrolled where it was.
- [ ] Turn on Scrolls for a screen in the sidebar: the canvas shows the content area with the dashed viewport line.
  Cmd-Z turns it off again.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Can a region drawn under a scrolling region's frame, inside its content area but not in view, become its child? | No. A scrolling region takes a child only where it overlaps the frame at its scroll position; scroll first to place children in hidden content. | |
| How is a scrollable region's content shown? | Clipped to the frame, with scroll indicators, and a dashed outline of the whole content area while selected. | |
| Does scrolling move by the trackpad's full delta? | Yes, divided by the zoom, so content follows the fingers. | |
| What does turning on a screen's Scrolls set? | Vertical, content as wide as the viewport and twice as tall, as for regions. | |
