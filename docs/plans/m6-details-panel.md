# Details panel (milestone 6)

How milestone 6 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on
[m5-tools-gestures.md](m5-tools-gestures.md).

**Status:** shipped

## Goal

Afterwards a region gets its title, description, kind, links and scrolling in a details panel on the right. Drawing a
region, clicking one with the Write tool, or double-clicking one with the Select tool slides the panel in with the
title focused while the canvas zooms to fit the region; Escape commits and the canvas animates back. A whole panel
session is one undo step, a new region left without a title disappears, and no canvas keybind fires while typing.

## Scope

**In:**

- `RegionEditor` in the core: one region open in the panel. It applies each field change to the project as it
  happens (so the canvas shows the title while it is typed), and on commit records the whole session as one undo
  step, applying the blank-title rules (roadmap D2). Cancelling reverts everything and records nothing.
- `EditSession` gains `applyWithoutRecording(_:)` and `record(_:)`, so changes built up over a session become one
  step.
- `CanvasGesture` reports what the panel should do on release: open a region (Write click, Select double-click),
  close (Write click on empty canvas). A Region-tool draw creates its region with a blank title.
- The panel (spec 6.2): Title, Description, Kind, Links (target screen and optional trigger per link, with add and
  remove) and Scrolling (off by default; axis, content width and content height when on).
- Keys (spec 6.3): Return in the title moves to the description; Return in the description inserts a line; Tab and
  Shift-Tab move between fields, from the description too; Escape commits and closes from any field.
- Opening slides the panel in and animates the canvas to fit the region in the space left of it; closing slides it
  out and animates the canvas back to the zoom and pan it had before. Switching regions (spec 6.4) commits the
  current one and refits to the new one.
- Cmd-Z while a panel field is being edited undoes typing in that field, through an undo manager of the panel's
  own, so typing never leaves steps on the document's stack. Undo or redo of a document step while the panel is
  open (from the Edit menu, or with a pop-up focused) first reverts the open session and closes the panel. Any other
  edit commits and closes it first. Switching screens commits and closes it.
- Core helpers with tests: kind display names, the default scroll settings when Scrolling is turned on, clamping
  content sizes, the default target of a new link, and camera interpolation for the zoom animations.

**Out:**

- Drawing the content area, scrolling inside a region, clipping, and re-parenting when a region's scroll content
  changes (milestone 9). The panel only stores the scroll settings.
- The link indicator on the canvas, Cmd-click and `L` to follow links (milestone 8).
- Showing descriptions on the canvas with `D` and `Shift-D` (milestone 7).
- Editing several regions at once. The panel always shows one region.
- Committing the panel when the window closes or the document saves; autosave writes the live values, and the
  milestone 12 hardening pass revisits closing with the panel open.

**Decision:** the panel is AppKit, not SwiftUI as roadmap D1 suggests for panels. Return, Tab, Shift-Tab and
Escape have to be redirected inside text views, which AppKit does reliably through `doCommandBy` delegate methods
and SwiftUI's `TextEditor` on macOS 14 does not (Tab inserts a tab character). It is still a thin view over the
core's `RegionEditor`.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Unrecorded changes in the edit session | `…/Commands/EditSession.swift` | none |
| 2 | Region editor and field helpers | `…/Editing/RegionEditor.swift`, `…/Model/Values.swift` | 1 |
| 3 | Gesture requests and camera interpolation | `…/Editing/CanvasGesture.swift`, `…/Layout/Camera.swift` | none |
| 4 | Model and document wiring | `InterfaceDescriber/DocumentModel.swift`, `InterfaceDescriber/Document.swift` | 2 |
| 5 | The panel | `InterfaceDescriber/DetailsPanelController.swift` | 4 |
| 6 | Canvas, window and animations | `InterfaceDescriber/CanvasViewController.swift`, `InterfaceDescriber/CanvasView.swift`, `InterfaceDescriber/DocumentWindowController.swift` | 3, 4, 5 |

1. **Unrecorded changes.** `EditSession.applyWithoutRecording(_:)` applies a command and returns its inverse without
   touching the undo or redo stacks. `record(_:)` pushes an inverse for changes already applied as one undo step and
   clears redo. Tests: applying without recording leaves `undoDepth` alone; recording adds one step that undo
   reverses and redo repeats.
2. **Region editor.** `RegionFields` holds title, description, kind, links and scroll. `RegionEditor(region:in:)`
   opens an existing region; `RegionEditor(creating:in:)` applies a `CreateRegion` without recording it and opens
   the new region. `setTitle`, `setDescription`, `setKind`, `setLinks` and `setScroll` apply the change at once.
   `commit()` trims the title; then a new region with a blank title is removed and nothing is recorded; an
   existing region with a blank title gets its old title back; an existing region with nothing changed records
   nothing; otherwise one step is recorded: "New Region" for a new region, the field's own name ("Edit Title",
   "Change Kind", …) when one field changed, "Edit Region" for several. `cancel()` puts everything back and records
   nothing. Helpers: `RegionKind.displayName` ("Open", "Menu Item"), `Scroll.defaultFor(_:)` (vertical, content
   as wide as the frame and twice as tall), `Scroll.clamped(to:)` (content at least the frame's size),
   `RegionEditor.newLinkTarget(in:)` (the first screen other than the region's own, else its own). Tests for each
   rule, that undo after a commit restores every field, and that redo after undoing a new region brings it back
   with its title.
3. **Gesture requests and camera interpolation.** `CanvasGesture` takes the press's click count and exposes
   `detailsRequest` after release: `.open(id)` for a Write click on a region or a Select double-click on one,
   `.close` for a Write click on empty canvas, nil otherwise. A drawn region's title is blank. `Camera.interpolated(
   from:to:fraction:viewSize:)` moves zoom geometrically and the view's center point linearly, giving the start at 0
   and the end at 1. Tests for each.
4. **Model and document.** `DocumentModel` holds the open `RegionEditor` as `details`, with `openDetails(for:)`,
   `openDetails(creating:)` (both commit any open region first and select the region), `editDetails(_:)`,
   `closeDetails()` and `cancelDetails()`. A recorded commit calls back to the document, which registers the
   `NSUndoManager` step. `Document.perform` commits and closes the panel first; undo and redo cancel it first.
   App tests: a drawn and titled region is one "New Region" step that undo removes; a blank one leaves no region and
   no step; clearing an existing title reverts it; undo while open reverts the session and closes the panel.
5. **The panel.** `DetailsPanelController`, an AppKit form in a scroll view inside the window's inspector slot:
   title field, description text view, kind pop-up, a links list (screen pop-up, trigger field, remove button per
   link, and an Add Link button), and a Scrolls checkbox with axis pop-up and content width and height fields that
   show only while it is on. Every change goes through `DocumentModel.editDetails`. Return, Tab, Shift-Tab and
   Escape are handled in `control(_:textView:doCommandBy:)` and `textView(_:doCommandBy:)`; Escape from a non-text
   control reaches `cancelOperation(_:)` through the responder chain. App tests drive these methods directly.
6. **Canvas, window and animations.** The canvas passes the click count and acts on `detailsRequest` and on a
   drawn region by opening the panel. The window controller watches `details`: on open it expands the inspector
   (animated) and focuses the title; the canvas controller remembers the camera and animates to
   `Camera.fitting` the region in the canvas width left of the panel (padding 40, at most 4×); on switching it refits;
   on close it collapses the inspector, animates back to the remembered camera, and gives the canvas focus.
   Camera animations run 0.25 s with ease-in-out, are not saved as the user's camera, and are instant in tests.
   App tests: opening fits the region and closing restores the camera; Write click opens and switches; Select
   double-click opens; bare-key Tools menu items are disabled while the title is being edited.

## Done when

**Tests and CI:**

- [ ] (Core) Changes applied without recording leave the undo stack alone; `record` adds one step that undo and redo
  reverse and repeat.
- [ ] (Core) A new region committed with a title is one "New Region" step; with a blank or whitespace title it is
  removed and nothing is recorded.
- [ ] (Core) An existing region's cleared title reverts; a blank description is kept; an unchanged session records
  nothing; several changed fields are one "Edit Region" step that undo fully reverses.
- [ ] (Core) A Write click on a region and a Select double-click on a region request opening it; a Write click on
  empty canvas requests closing; a drawn region's title is blank.
- [ ] (Core) Camera interpolation starts at the first camera and ends at the second.
- [ ] (App) Drawing a region opens the panel with the title field focused, and the canvas fits the region; Escape
  commits, closes the panel and restores the camera.
- [ ] (App) Return in the title moves focus to the description; Tab in the description moves to the next field.
- [ ] (App) Undo while the panel is open reverts the session and closes the panel.
- [ ] (App) The Tools menu's bare-key items are disabled while the title field is being edited.
- [ ] (App) The panel's text fields use the panel's own undo manager (through their own field editor), so Cmd-Z
  while typing undoes typing; with the canvas focused, undo is the document's.
- [ ] (App) Kind, a link with a trigger, and scrolling set in the panel are one "Edit Region" step.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Drawing a region slides the panel in, zooms the canvas to the region, and puts the cursor in Title; typing
  shows the title on the canvas.
- [ ] Return moves to Description, where Return adds lines; Tab and Shift-Tab walk the fields; Escape closes the
  panel and the canvas animates back.
- [ ] Escape on a new region with no title removes it; clearing an existing title and pressing Escape restores it.
- [ ] Cmd-Z after closing undoes the whole session in one step.
- [ ] With the Write tool, clicking another region switches the panel to it and refits; clicking empty canvas closes
  the panel. Double-clicking a region with the Select tool opens it.
- [ ] Kind, links (add, choose a screen, type a trigger, remove) and Scrolling save and survive closing and
  reopening the document.
- [ ] Typing `R`, `V` or `S` into any panel field types the letter and changes no tool or setting.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| How far does zoom-to-fit zoom in on a small region? | At most 4×, so a small icon doesn't fill the canvas. | |
| What does turning Scrolling on set? | Vertical, content as wide as the frame and twice as tall. | |
| Can scroll content be smaller than the frame? | No; width and height are raised to the frame's size. | |
| What happens to the panel when another edit happens (a drag, a delete)? | The panel commits and closes first. | |
| Does a plain Select-tool click on another region switch the panel? | No; only a Write click or Select double-click switches (spec 6.4). | |
