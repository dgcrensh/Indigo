# Tools, gestures, toasts and keybinds (milestone 5)

How milestone 5 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on
[m2-commands.md](m2-commands.md) and [m4-canvas-rendering.md](m4-canvas-rendering.md).

**Status:** shipped

## Goal

Afterwards the canvas can be edited with the mouse: `V`, `R` and `W` pick the Select, Region and Write tools with a
toast, the Region tool draws regions anywhere (the parenting rule picks the parent), and the Select tool selects,
moves, resizes and marquee-selects them, snapping to the grid unless `S` turns snapping off or Option is held. `G`
opens a grid-size slider. Every drag is one undo step, and every keybind comes from a `KeybindRegistry` holding
the spec Section 9 defaults.

## Scope

**In:**

- `Tool` (Select, Region, Write) and the active tool and selection in the document model.
- `KeybindRegistry` in the core: every spec Section 9 action with its default key combinations, lookup from a key
  combination to an action, overrides (for milestone 10's settings file), parsing and display of combinations, and
  which actions stay live while text is being edited. Tests for all of it.
- Gesture logic in the core, with tests: hit testing regions and resize handles, marquee selection, click versus
  drag, and the frames a draw, move or resize gesture previews and commits, with snapping, Option inversion and the
  4 × 4 pt minimum.
- The canvas routes mouse events into that logic: previews while dragging, one command on release, selection
  drawn as an accent border with eight resize handles on a single selected region, and cursors for the Region tool
  and the handles.
- Toasts near the bottom center of the canvas for tool changes, snapping on or off, and grid size.
- The `G` popover: a slider over the grid steps 4, 8, 12, 16, 24 and 32 pt. The grid shows while it is open, even
  with snapping off. The grid size is saved per screen in the editor state.
- A Tools menu with Select Tool, Region Tool, Write Tool, Snap to Grid (checked while on) and Grid Size…, with key
  equivalents from the registry. Existing menu items for spec Section 9 actions (zoom, undo, redo, copy, paste,
  select all, toggle sidebar) take their key equivalents from the registry too.

**Out:**

- The details panel (milestone 6). Until it exists, a region drawn with the Region tool is created with the title
  "Region" and selected; the Write tool's click selects the region under it (or clears the selection on empty
  canvas); a Select-tool double-click does nothing extra. Milestone 6 replaces these with opening the panel.
- Delete, copy, paste, duplicate, nudge, Select All, Select Parent and Children, bring to front and send to back,
  and `D` / `Shift-D` (milestone 7). The registry has their defaults, but nothing is wired to them yet.
- Cmd-click and `L` to follow links, Back and Forward, next and previous screen (milestone 8). Cmd-click selects
  like a click for now.
- Scrolling inside a region (milestone 9).
- Reading keybind overrides and the snap default from `settings.json` (milestone 10). The registry accepts
  overrides; nothing supplies them yet. Snapping starts on in every window.
- Undo for the tool, the selection, snapping and the grid size. They are editor state, not edits.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Keybind registry | `Packages/DescriberCore/Sources/DescriberCore/Editing/Keybinds.swift` | none |
| 2 | Tools, toasts and selection | `…/Editing/Tool.swift`, `…/Editing/Selection.swift` | 1 |
| 3 | Hit testing and handles | `…/Layout/HitTesting.swift` | none |
| 4 | Gesture logic | `…/Editing/CanvasGesture.swift`, `…/Commands/RegionCommands.swift` | 2, 3 |
| 5 | Canvas: selection, handles, previews, cursors, toasts | `InterfaceDescriber/CanvasView.swift`, `InterfaceDescriber/RegionLayers.swift`, `InterfaceDescriber/CanvasColors.swift`, `InterfaceDescriber/ToastView.swift` | 4 |
| 6 | Controller, model and the grid popover | `InterfaceDescriber/CanvasViewController.swift`, `InterfaceDescriber/DocumentModel.swift`, `InterfaceDescriber/GridSizePopover.swift`, `InterfaceDescriber/Document.swift`, `InterfaceDescriber/DocumentWindowController.swift` | 5 |
| 7 | Menus from the registry | `InterfaceDescriber/MainMenu.swift`, `InterfaceDescriber/Keybinds+AppKit.swift` | 1, 6 |

1. **Keybind registry.** `KeyCombo` is a key (a lowercase character, or a named key: `return`, `delete`,
   `forward-delete`, `escape`, `tab`, `space`, `left`, `right`, `up`, `down`) and a set of modifiers (`cmd`,
   `shift`, `option`, `ctrl`). `KeyCombo(parsing:)` reads strings such as `v`, `shift-d`, `cmd-option-left`,
   `cmd-]` and `cmd--` (case-insensitive; `command`, `alt` and `control` also accepted), and `description` writes
   them back in that form; `displayString` gives the menu form, such as `⇧D` or `⌥⌘←`. `KeyAction` lists every
   spec Section 9 action except holding Option, which is a modifier read during a gesture. `KeybindRegistry`
   has `defaults` (spec Section 9; Zoom In is Cmd + and Cmd =, Delete is Delete and Forward Delete), `init(overrides:)`,
   `combos(for:)` and `action(for:isEditingText:)`. An override replaces the action's combinations, and a
   combination an override claims is taken from whichever action had it by default. While text is being edited
   only undo, redo, copy, paste and select all resolve. Tests: every action has a default; parsing and describing
   round-trip; the spec defaults resolve (`v`, `shift-return`, `cmd-option-left`); an override moves a
   combination; bare keys don't resolve while editing text; a bad string doesn't parse.
2. **Tools, toasts and selection.** `Tool` is `select`, `region` and `write`, each with its name ("Region tool")
   and its `KeyAction`. `Toast` gives the text for a tool change ("Region tool — R", with the key from a
   registry), snapping ("Snapping on — S", "Snapping off — S") and grid size ("Grid 8 pt"). `Selection` helpers:
   toggling a region, and keeping only the selected regions still on a screen. Tests for the texts and helpers.
3. **Hit testing and handles.** `HitTesting.region(at:in:)` is the topmost region (highest draw order) whose frame
   contains the point, edges included. `HitTesting.regions(touching:in:)` lists every region a rectangle
   overlaps, in draw order; a zero-size rectangle touches nothing. `ResizeHandle` has the eight handles (four
   corners and four edge midpoints), each with the `Snapping.Edges` it drags, its point on a rectangle, and
   `ResizeHandle.handle(at:on:radius:)`, which picks the nearest handle within the radius. Tests for each,
   including overlapping and nested regions and a handle on a tiny region.
4. **Gesture logic.** `CanvasGesture` is one press-drag-release, created from the press with a `GestureContext`
   (screen, tool, selection, snapping on, grid size, zoom). `drag(to:optionHeld:)` and `release(at:optionHeld:)`
   update it; it exposes the selection, a preview (frames for moved or resized regions, the new region's frame,
   or the marquee rectangle) and, on release, the command to perform. Snapping applies when
   `Snapping.isActive(enabled:optionHeld:)` says so at each event. A press moves less than 3 view points before
   it counts as a drag.
   - Select tool, on the single selected region's handle: resize. The opposite edges stay put, the frame never
     goes below 4 × 4 pt (a handle dragged past the opposite edge stops there), dragged edges snap, and if
     snapping would shrink it below the minimum the edge goes to the next grid line outward. Commits
     `ResizeRegion` when the frame changed.
   - Select tool, on a region: a press selects it unless it is already selected; Shift toggles it instead. A drag
     moves the selection (the topmost selected regions, descendants with them), snapping the first one's origin;
     commits one `MoveRegions` when the delta isn't zero. A click without a drag on a region that is part of a
     larger selection selects just that region. Shift on a region it just deselected doesn't move anything.
   - Select tool, on empty canvas: a press clears the selection (Shift keeps it), and a drag marquee-selects
     every region it touches, added to the kept selection with Shift.
   - Region tool: a drag draws a frame from the press point to the pointer, in any direction, every edge snapped.
     A drag under 4 × 4 pt before snapping is a click and does nothing; if snapping collapses a side, it spans
     one grid step in the drag's direction. Commits `CreateRegion` titled "Region" and selects it.
   - Write tool: a click selects the region under it or clears the selection; drags do nothing.
   - `MoveRegions` takes its snapped delta from a shared function the gesture also uses, so the preview and the
     result agree.
   Tests for every case above, including that a drag commits exactly one command, Option inverts snapping both
   ways, and the committed command applied to the screen gives the previewed frames.
5. **Canvas.** `CanvasView` draws the selection as a 2 pt accent border on each selected region and, when exactly
   one region is selected with the Select tool, eight 7 pt square handles that stay that size at every zoom. During
   a gesture it shows the preview: moved or resized region layers take the preview frames (with their
   out-of-bounds tints), a new region shows as an accent rectangle, and the marquee as a translucent rectangle. It
   turns mouse down, dragged and up (and Option changes mid-drag) into calls on its controller, in screen points.
   Cursors: crosshair for the Region tool, left-right and up-down resize cursors over edge handles and a
   crosshair over corner handles, the arrow otherwise. `ToastView` is a rounded label near the bottom center that
   never takes clicks or focus, shows for about a second and fades.
6. **Controller, model and popover.** `DocumentModel` gains `tool`, `selection` (pruned to the active screen's
   regions after every change and cleared when the screen changes) and the grid size per screen. The controller
   builds the gesture context, applies previews, and performs the committed command through `Document.perform`, so
   a drag is one undo step. `selectTool(_:)`, `toggleSnapping()` and `showGridSize()` live on the window
   controller and show toasts. The grid popover (SwiftUI in an `NSPopover`) is a slider with the six steps, shows
   the current size, writes it to `project.editorState.screens[id].gridSize` (keeping the current camera when the
   screen had no saved state), shows a toast and redraws the grid; the grid stays visible while it is open. `G`
   again closes it. The canvas also handles the tool keys in `keyDown` through the registry, in case a menu key
   equivalent doesn't reach it. App tests: drawing, moving and resizing through the controller each add one undo
   step and undo restores the frames; a marquee selects the regions it touches; `R` in the canvas switches tools
   and shows the toast; changing the grid size doesn't move any region.
7. **Menus from the registry.** A small AppKit extension turns a `KeyCombo` into a key equivalent and modifier
   mask. A Tools menu after View holds Select Tool, Region Tool, Write Tool (checked for the active tool), Snap
   to Grid (checked while on) and Grid Size…. The window controller validates them, and disables the bare-key
   items while a text field is being edited. Zoom In, Zoom Out, Actual Size, Toggle Sidebar, Undo, Redo, Copy,
   Paste and Select All take their key equivalents from the registry. App tests: each Tools item has its spec key;
   existing key equivalents are unchanged.

## Done when

**Tests and CI:**

- [ ] Every spec Section 9 action has a default in the registry; `v`, `shift-return` and `cmd-option-left`
  resolve to Select tool, Select parent and Back; an override moves a combination off its default action.
- [ ] While text is being edited, bare keys resolve to nothing and Cmd-Z still resolves to Undo.
- [ ] Hit testing picks the topmost region; the marquee picks every region it touches.
- [ ] A Region-tool drag commits one `CreateRegion` whose frame is snapped, and a drag under 4 × 4 pt commits
  nothing.
- [ ] A Select-tool drag on a region commits one `MoveRegions` that moves the whole selection; Shift-click toggles
  a region; a click on empty canvas clears the selection.
- [ ] A handle drag commits one `ResizeRegion` that never goes below 4 × 4 pt and snaps only the dragged edges.
- [ ] Option inverts snapping for the gesture, both with snapping on and off.
- [ ] (App) Drawing, moving and resizing each add exactly one undo step, and undo restores the frames.
- [ ] (App) Pressing `R` in the canvas selects the Region tool and shows "Region tool — R".
- [ ] (App) Changing the grid size moves no region and is saved in the editor state.
- [ ] (App) The Tools menu has the three tools, Snap to Grid and Grid Size… with `V`, `R`, `W`, `S` and `G`.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] `V`, `R` and `W` switch tools, and a toast near the bottom of the canvas names the tool and fades.
- [ ] With the Region tool, dragging inside Login's sign-in form draws a region that becomes its child (moving the
  form afterwards moves it too).
- [ ] With the Select tool, dragging a region moves it with snapping; holding Option moves it freely; `S` turns
  snapping off (toast, grid hidden) and Option then snaps.
- [ ] Dragging a handle resizes a region; it stops at 4 × 4 pt; Cmd-Z undoes the whole drag in one step.
- [ ] Dragging on empty canvas draws a marquee that selects every region it touches; Shift-click adds and removes.
- [ ] `G` opens the grid slider; moving it changes the grid lines and shows a toast; no region moves.
- [ ] Debug > New 500-Region Document: dragging a container with all its rows stays smooth.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| What does a region drawn before the details panel exists get as its title? | "Region", so it shows on the canvas; milestone 6 opens the panel with the title blank instead. | |
| Is changing the grid size undoable? | No. It is editor state like zoom, and it never moves a region. | |
| Does the active tool persist across windows or relaunches? | No. Every window starts with the Select tool and snapping on. | |
| What does a Shift-drag on empty canvas do? | Adds the regions the marquee touches to the selection. | |
