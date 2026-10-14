# Selection and editing (milestone 7)

How milestone 7 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on
[m5-tools-gestures.md](m5-tools-gestures.md) and [m6-details-panel.md](m6-details-panel.md).

**Status:** shipped

## Goal

Afterwards the selection can be built and edited from the keyboard and the Edit menu, as spec Section 7 describes:
Cmd-A selects every region on the screen, `Shift-Return` and `Return` walk up to the parent and down to the
children, Delete removes the selection (asking first when it has children), Cmd-C, Cmd-V and Cmd-D copy, paste and
duplicate regions (onto another screen too), the arrow keys nudge, and Cmd-] and Cmd-[ bring the selection to the
front or send it to the back of its siblings. `D` and `Shift-D` show descriptions on the canvas, read-only, for the
selection or for every region on the screen.

## Scope

**In:**

- Selection helpers in the core: all regions on a screen, the parents of the selection, the children of the
  selection.
- A region clipboard in the core: the selection's topmost regions (with their subtrees) as JSON in the screen file's
  region format, read back into regions, and turned into a `PasteRegions` with new IDs. Links are kept, except links
  to screens the target project doesn't have (a paste from another document). A paste that would land exactly on a
  region with the same frame moves one grid step right and down until it doesn't, so pasting onto the source screen
  and duplicating show the copy beside the original, and pasting onto another screen keeps the frames.
- `PasteRegions` takes an action name, so a duplicate is one "Duplicate" step and a paste one "Paste" step.
- `ReorderRegions` in the core: brings several regions to the front or back of their own siblings, keeping their
  order among themselves. Nothing to reorder is an error, so it records no step.
- Nudging in the core: the delta for each nudge action, one grid step (four with Shift), or 1 pt and 4 pt with
  snapping off (`Snapping.nudgeDistance`). A nudge is one `MoveRegions` step without grid snapping, so a region off
  the grid stays off it by the same amount.
- Delete confirmation text in the core, for a selection that has regions inside it: "Delete “Sign-in form” and
  the 2 regions inside it?" for one region, "Delete 3 regions and the 5 regions inside them?" for several.
- Description visibility in the core: toggling a set of regions (all shown already, so hide them; otherwise show
  them all), used by `D` for the selection and `Shift-D` for every region on the active screen. It is editor state
  in `.editor-state.json` (spec 3.1), like zoom: not undoable and not an edit.
- The canvas draws a shown, non-empty description under the title, wrapped and clipped to the region.
- The app: Edit menu items Copy, Paste, Duplicate, Delete, Select All, Select Parent, Select Children, Bring to
  Front, Send to Back and a Nudge submenu; View menu items Toggle Description and Toggle All Descriptions. Key
  equivalents come from the registry. Copy and paste use the general pasteboard with a private type, plus the
  titles as plain text.
- Keys without Cmd (Delete, Return, Shift-Return, the arrows, `D`, `Shift-D`) work only while the canvas has focus,
  so they never take keys from text fields, pop-ups or the sidebar. Cmd-D, Cmd-] and Cmd-[ are off while text is
  being edited; Cmd-C, Cmd-V and Cmd-A then go to the text (spec 6.3).
- Every edit commits and closes an open details panel first, as milestone 6 set up.

**Out:**

- Cut. Spec Section 7 lists copy, paste and duplicate only; the Cut menu item stays inactive outside text.
- Following links with Cmd-click or `L` (milestone 8).
- Resizing several regions at once. Resize stays single-region (spec 7), as milestone 5 built it.
- Merging consecutive nudges into one undo step. Each nudge is its own step.
- Pruning the IDs of deleted regions from `visibleDescriptions` on save (milestone 12 hardening, if it matters).
- Toasts for `D` and `Shift-D`; spec Section 4 lists toasts for tools, snapping and grid size only.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Selection, nudge, delete prompt and description helpers | `…/Editing/Selection.swift`, `…/Editing/EditingActions.swift` | none |
| 2 | Region clipboard and paste placement | `…/Editing/RegionClipboard.swift`, `…/Format/ProjectDecoding.swift`, `…/Commands/RegionCommands.swift` | none |
| 3 | Reordering several regions | `…/Commands/RegionCommands.swift` | none |
| 4 | Descriptions on the canvas | `InterfaceDescriber/RegionLayers.swift`, `InterfaceDescriber/CanvasView.swift`, `InterfaceDescriber/CanvasColors.swift` | 1 |
| 5 | Editing actions in the canvas controller | `InterfaceDescriber/CanvasViewController.swift` | 1, 2, 3, 4 |
| 6 | Menus and validation | `InterfaceDescriber/MainMenu.swift`, `InterfaceDescriber/DocumentWindowController.swift` | 5 |

1. **Helpers.** `Selection.all(on:)` lists every region in draw order. `Selection.parents(of:on:)` gives the
   parents of the selected regions, without repeats, in selection order; top-level regions add nothing.
   `Selection.children(of:on:)` gives the direct children of the selected regions, without repeats. `Nudge.delta(for:
   grid:snapping:)` maps the eight nudge actions to a delta. `DeleteConfirmation.message(deleting:on:)` gives the
   text above, or nil when no selected region has children. `DescriptionVisibility.toggling(_:in:)` returns the new
   set of shown regions. Tests for each, including an empty selection, a top-level region's parent, and a selection
   that holds a parent and its child.
2. **Clipboard.** `RegionClipboard` holds the source screen's ID and copies of the regions. `RegionClipboard(copying:
   on:)` takes the topmost selected regions in draw order. `data(in:)` writes `{"screen": …, "regions": […]}` with
   the screen file's region encoder; `RegionClipboard(data:)` reads it back through the screen file's region decoder
   (bad data throws). `paste(onto:in:grid:actionName:)` returns a `PasteRegions` with the links filtered and the
   offset applied. Tests: copy and read back round-trips; a parent and its child copy once; links to missing screens
   are dropped; pasting onto the source screen offsets by one grid step and a second paste by two; pasting onto
   another screen keeps the frames; pasted IDs are new.
3. **Reordering.** `ReorderRegions(screen:regions:to:)` moves the selected regions in each sibling list to the end
   (front) or start (back), keeping their relative order, and throws `nothingToDo` when nothing moves. Undo restores
   the order. Tests: two siblings brought to the front keep their order; regions in different parents reorder within
   their own parents; already at the front throws.
4. **Descriptions on the canvas.** `RegionLayers` gains a description text layer, 10 pt, wrapped, in the secondary
   label color, under the title and clipped to the region, shown when the region's ID is in `visibleDescriptions` and
   its description isn't blank. `CanvasView.visibleDescriptions` sets it on every region layer.
5. **Controller.** `CanvasViewController` gains `selectAll()`, `selectParent()`, `selectChildren()`,
   `deleteSelection()`, `copySelection()`, `paste()`, `duplicate()`, `nudge(_:)`, `reorderSelection(to:)` and
   `toggleDescriptions(all:)`, and `handle(_:)` routes their key actions. Each edit closes the details panel first,
   then performs one command; paste and duplicate select the copies. Delete asks through `confirmDelete` (a sheet on
   the window; tests replace it). The pasteboard is a property so tests use a private one. `nothingToDo` doesn't
   beep. App tests: Cmd-A then Delete removes every region in one step; deleting a parent asks and a "no" deletes
   nothing; copy and paste onto another screen keeps frames and links and selects the copies; duplicate is one
   "Duplicate" step beside the original; an arrow nudges by the grid step and Shift-arrow by four; Shift-Return and
   Return walk up and down; bring to front is undoable; `D` shows the selection's descriptions and `Shift-D` all of
   them, without an undo step.
6. **Menus.** Edit gets Duplicate, Delete (Delete and Forward Delete), Select Parent, Select Children, Bring to Front,
   Send to Back and a Nudge submenu; View gets Toggle Description and Toggle All Descriptions. The window controller
   handles `copy:`, `paste:`, `selectAll:` and `delete:` when no text view takes them, and validates every item:
   enabled when there is something to act on, bare-key items only while the canvas has focus, Cmd items other than
   copy, paste and select all off while text is being edited. App tests: each item has its spec key; the bare-key
   items are disabled while the title field is being edited.

## Done when

**Tests and CI:**

- [ ] (Core) Select all, select parent and select children give the spec results, including a parent covered by its
  children and a top-level region with no parent.
- [ ] (Core) Copied regions read back from the clipboard data; pasted copies get new IDs throughout, keep links to
  screens in the project, drop others, and sit one grid step away on the source screen and in place elsewhere.
- [ ] (Core) Bringing several regions to the front or back keeps their order among themselves, and undo restores it.
- [ ] (Core) Nudge deltas are one grid step, four with Shift, and 1 pt and 4 pt with snapping off.
- [ ] (Core) The delete confirmation names the region and counts the regions inside, and is nil without children.
- [ ] (Core) Toggling descriptions shows all when any is hidden and hides all when all are shown.
- [ ] (App) Select All then Delete removes every region in one undo step; deleting a parent asks, and declining
  deletes nothing.
- [ ] (App) Copy and paste onto another screen and Duplicate each add one step and select the copies.
- [ ] (App) Arrow and Shift-arrow nudges, Shift-Return, Return, and bring to front and send to back work through
  the controller.
- [ ] (App) `D` and `Shift-D` change `visibleDescriptions` and the canvas's description layers without an undo step.
- [ ] (App) The new menu items have their spec keys, and the bare-key ones are disabled while a text field is being
  edited.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Cmd-A selects every region; Delete removes them; Cmd-Z brings them all back in one step.
- [ ] Deleting the sign-in form asks first and deletes its fields with it.
- [ ] Select a field inside the sign-in form and press `Shift-Return`: the form is selected. `Return` selects its
  fields again.
- [ ] Cmd-C a region, switch to another screen, Cmd-V: it appears at the same place. Cmd-D shows a copy one grid step
  right and down of the original.
- [ ] Arrows nudge by the grid step, Shift-arrows by four steps, and by 1 pt and 4 pt with snapping off.
- [ ] Cmd-] and Cmd-[ move a region above and below an overlapping sibling.
- [ ] `D` shows the selected region's description on the canvas, `D` again hides it; `Shift-D` shows and hides all.
  The setting survives closing and reopening the document.
- [ ] Typing in the details panel's fields never nudges, deletes or selects on the canvas.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Where do pasted and duplicated regions go? | In place, moved one grid step right and down while that would cover a region with the same frame. | |
| What happens to links when pasting into another document? | Links to screens it doesn't have are dropped. | |
| What does `Shift-Return` do with several regions selected? | Selects each one's parent; top-level regions add nothing; nothing changes if none has a parent. | |
| Does `Shift-D` act on the screen or the whole project? | The active screen. | |
| Are several nudges in a row one undo step? | No, each nudge is a step. | |
