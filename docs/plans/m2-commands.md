# Command layer, parenting, snapping (milestone 2)

How milestone 2 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on [m1-file-format.md](m1-file-format.md).

**Status:** shipped

## Goal

Afterwards every edit the spec allows on regions, links and screens exists as a tested, undoable command in the
core, with the parenting rule and snapping applied the way spec Section 5 describes. Nothing is visible in the
app yet; milestones 3 onward wire these commands to the UI instead of writing edit logic of their own.

## Scope

**In:**

- A `Command` protocol and an `EditSession` that applies commands and keeps undo and redo stacks.
- Region commands: create, move, resize, delete, edit title, description, kind, links and scroll, reorder among
  siblings, paste.
- Screen commands: add, rename, duplicate, reorder, delete (removing incoming links), set kind, set viewport,
  new variant, group and ungroup variants.
- The parenting rule, the minimum size, and snapping math.

**Out:**

- `NSUndoManager` (milestone 3). The app bridges `EditSession` to it; the core doesn't import AppKit.
- Gesture handling, live drag previews, and deciding when a gesture ends (milestone 5). The core receives a
  final frame per gesture.
- Details-panel rules such as discarding a blank new region (milestone 6). The core provides the delete command
  the panel uses for that.
- Clipboard formats and pasteboard access (milestone 7). Here paste takes regions already decoded.
- Scroll-in-region gestures (milestone 9). Here only the content area used by parenting.
- Viewport presets, This Device, and settings (milestones 8 and 10). Set viewport takes a `Viewport` value.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Command protocol and edit session | `Packages/DescriberCore/Sources/DescriberCore/Commands/EditSession.swift`, `…/Commands/Command.swift` | none |
| 2 | Region index and tree helpers | `…/Model/RegionIndex.swift` | none |
| 3 | Parenting rule and minimum size | `…/Layout/Parenting.swift` | 2 |
| 4 | Snapping | `…/Layout/Snapping.swift` | none |
| 5 | Region commands | `…/Commands/RegionCommands.swift` | 1, 2, 3 |
| 6 | Screen and link commands | `…/Commands/ScreenCommands.swift` | 1, 2 |

1. **Command protocol and edit session.** `Command` has `apply(to: Project) throws -> Command`, returning its
   inverse, and an `actionName` for the Undo menu ("Move Region", "Rename Screen"). `EditSession` owns a
   `Project`, `perform(_:)`, `undo()`, `redo()`, `canUndo`, `canRedo`, and `undoActionName`. A `CompositeCommand`
   applies several commands as one undo step. Performing a new command clears redo. A command that throws leaves
   the project unchanged. Tests: undo and redo restore the encoded project bytes exactly (using the milestone 1
   encoder), composite undo is one step.
2. **Region index and tree helpers.** `RegionIndex` per screen maps `RegionID` to region, parent, and sibling
   index, rebuilt after each command. Helpers: descendants of a region, path from root, and the content area
   (the frame, or origin plus `contentWidth` × `contentHeight` when the region scrolls).
3. **Parenting rule and minimum size.** `Parenting.parent(for frame:, excluding:, in screen:) -> RegionID?`
   returns the smallest region whose content area fully contains the frame; on equal area, the one drawn on top
   (later in a depth-first, sibling-order walk); the region itself and its descendants are excluded; `nil` means
   top level. `Parenting.reparentAfterChange(of:)` applies the rule to the changed region and to each former
   child of it that no longer fits. A re-parented region is appended as the last sibling of its new parent.
   `Geometry.minimumSize = 4`; frames below it in either dimension are rejected by the create and resize commands.
   Tests: draw inside a region, draw over two nested regions (the inner one wins), equal-size tie, drag into and
   out of a region, resize a parent so a child falls outside, a region exactly touching its parent's edge (still
   contained), scrolling content area.
4. **Snapping.** `Snapping.snap(_ value: Int, grid: Int) -> Int` and `snap(frame:grid:mode:)` for draw, move
   and resize, where move snaps the origin only and resize snaps the dragged edges only. `Snapping.isActive
   (enabled:optionHeld:)` returns `enabled != optionHeld`. Grid steps are the fixed list `[4, 8, 12, 16, 24, 32]`.
   Nudge distance: one step, four with Shift, 1 pt and 4 pt when snapping is off. Tests for each mode and for
   negative coordinates.
5. **Region commands.** Create (frame, title, optional parent override for paste), move (one or many regions by
   a delta, moving descendants with them), resize (one region to a frame), delete (one or many, with descendants),
   set title, set description, set kind, set links, set scroll, bring to front, send to back, and paste (regions
   with fresh IDs throughout the subtree, links kept). Create, move, resize, and paste run the parenting rule as
   part of the same command, so undo restores the old parent and sibling position. Rounding to whole points
   happens here. Tests for every command's apply and undo, and that moving a parent by (10, 20) moves every
   descendant by (10, 20).
6. **Screen and link commands.** Add (name, kind, viewport, position), rename, duplicate (new IDs throughout,
   links inside the copy kept pointing at their original targets), reorder, delete (also removes every link in
   the project that targets the screen, and drops the screen from its variant group), set kind, set viewport
   (regions untouched), new variant (duplicate into the same group with a new viewport, creating the group if
   needed), group and ungroup. `ScreenCommands.incomingLinks(to:)` lists the regions that would lose links, for
   the confirmation in milestone 8. Tests for each, and that undoing a screen delete restores the removed links.

## Done when

**Tests and CI:**

- [ ] Undoing any command restores the project so it encodes to the same bytes as before the command.
- [ ] Redo after undo produces the same bytes as the original apply.
- [ ] A `CompositeCommand` of three moves is one undo step.
- [ ] A region drawn inside two nested regions gets the inner one as its parent.
- [ ] Two equal-size candidates resolve to the one on top.
- [ ] Resizing a parent so a child no longer fits re-parents the child by the same rule, and undo puts it back.
- [ ] Creating or resizing to 3 × 10 pt is rejected and leaves the project unchanged.
- [ ] Changing nothing but grid size changes no frame (snapping only runs inside commands that move or resize).
- [ ] Snapping is active exactly when snap is enabled and Option is not held, or disabled and Option is held.
- [ ] Moving a parent moves all its descendants by the same delta.
- [ ] Pasted and duplicated regions and screens have all-new IDs and keep their links.
- [ ] Deleting a screen removes every link to it, and undo restores them.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Nothing new to see in the app; the milestone 0 and 1 checks still hold.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| When a region is re-parented, where does it go among its new siblings? | On top (last sibling). | |
| Does moving a region with Option-drag duplicate it, as in many design tools? | No; not in the spec. | |
| Should a region snapped to the grid also snap to other regions' edges? | No; grid only, as in the spec. | |
