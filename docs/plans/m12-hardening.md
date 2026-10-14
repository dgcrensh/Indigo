# Hardening and acceptance pass (milestone 12)

How milestone 12 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on every earlier plan, and audits the three
cross-cutting rules the roadmap left to this milestone: undo for every change, no canvas or tool keybind while text is
being edited, and smooth editing with 500 regions.

**Status:** shipped

## Goal

Afterwards every spec Section 13 criterion is either proven by a named test or listed as a check to do on the Mac,
in one place, [docs/acceptance.md](../acceptance.md). The three quality criteria have audits that fail when a later
change breaks them: a new command without an undo test, a menu item that fires while a field is being edited, or a
gesture that gets slow on the 500-region screen.

## Scope

**In:**

- **Undo audit, core.** A test that finds every type conforming to `Command` in the core's sources and fails if one
  is not exercised by the undo round-trip tests (undo restores the package byte for byte, redo reproduces it). The
  round-trip lists gain the commands they missed: `ReorderRegions`, `SetRegionScroll` turning scrolling on, and a
  `CompositeCommand`.
- **Undo audit, app.** One app test that drives every edit path a user has (canvas gestures, Edit menu, details
  panel, Screen menu and sidebar actions) on the example project and checks each is exactly one undo step whose undo
  restores the package's content files byte for byte and whose redo reproduces them. A second test drives every
  editor-only action (tools, snapping, grid size, selection, description visibility, zoom, scrolling inside a region,
  switching screens, following links) and checks none adds an undo step or changes a content file.
- **Keybind-suppression audit.** While a text field is being edited, every menu item whose key comes from the
  keybind registry is disabled unless its action is one of the standard editing shortcuts (Undo, Redo, Copy, Paste,
  Select All), whatever key it is bound to (spec 6.3 and 9). Today Zoom In, Zoom Out, Actual Size and Toggle Sidebar
  still fire while typing; the window controller's validation becomes one rule keyed on the registry action, and the
  sidebar toggle is validated by a small `NSSplitViewController` subclass that asks the same question. App tests
  walk the whole main menu with the title field being edited, with a description being edited, and with a bare-key
  override for Zoom In, and check the same items are enabled again once the canvas has focus.
- **500-region performance check.** `CanvasPerformanceTests` gains the gestures milestone 4 could not measure yet:
  moving one region, moving a selection of all 500, resizing a container with children, and drawing a new region,
  each driven through the canvas controller frame by frame on the stress screen. Each frame's time is printed and
  asserted under a CI budget (16 ms per drag frame, loose like milestone 4's), and the times are recorded in this
  plan.
- **Acceptance walk.** `docs/acceptance.md` lists every spec Section 13 criterion with the tests that prove it and
  the hand check on the Mac that remains. Gaps found while writing it are fixed in this PR if small, or listed under
  "Known gaps" there with the reason.
- The roadmap's milestone row and Section 4 point at the acceptance file.

**Out:**

- New features, settings or menu items. Anything the walk finds that needs one is a known gap, not a change here.
- Marking the document edited for zoom, pan or scroll alone. Milestone 4 decided those ride along with the next
  edit's save, and that stands.
- Running the Mac checks. They are listed for Dallas to do; a cloud session can't drive the app.
- Instruments profiling or a frame-rate overlay. The CI timings are the check; a hand check covers how it feels.
- Static analysis of the app sources for direct model writes. The app audit test and review cover that.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Core undo audit | `Packages/DescriberCore/Tests/DescriberCoreTests/CommandTests.swift` | none |
| 2 | Keybind suppression by registry action | `InterfaceDescriber/DocumentWindowController.swift`, `InterfaceDescriber/DocumentSplitViewController.swift` | none |
| 3 | App audits | `InterfaceDescriberTests/UndoAuditTests.swift`, `InterfaceDescriberTests/KeybindAuditTests.swift` | 2 |
| 4 | Gesture performance | `InterfaceDescriberTests/CanvasPerformanceTests.swift` | none |
| 5 | Acceptance file and roadmap | `docs/acceptance.md`, `docs/v1-roadmap.md`, this plan | 1–4 |

1. **Core undo audit.** `testEveryCommandTypeHasAnUndoTest` reads `Sources/DescriberCore/**/*.swift`, collects the
   names of types declared as conforming to `Command`, and compares them with the types the round-trip tests apply
   and the inverses those return (generic parameters dropped, composites walked). The round-trip lists add
   `ReorderRegions`, `RegionCommands.setScroll` with a scroll, and a composite of a move and a rename.
2. **Suppression.** `DocumentWindowController.validateMenuItem` first asks `MainMenu.keybind(of:)` for the item's
   registry action; while text is being edited an item with an action that doesn't work while editing text is
   disabled. Items without a registry key (Save, Close, the Screen menu) keep their own rules. The existing per-item
   `!isEditingText` checks fold into that rule. `DocumentSplitViewController` disables `toggleSidebar(_:)` by the same
   rule, through a closure the window controller gives it, so the split view never needs to know about the panel.
3. **App audits.** `UndoAuditTests` compares `ProjectPackage.write(project:).tree` without `.editor-state.json` before,
   after, after undo and after redo, for each path in a table, and checks the session's undo depth moves by exactly
   one. `KeybindAuditTests` walks `MainMenu.make()` recursively and validates each registry item through the object
   that would handle it (the split view controller for Toggle Sidebar, the window controller otherwise).
4. **Gesture performance.** Each gesture presses, drags 20 frames and releases through `CanvasViewController`, with
   layer display forced each frame as milestone 4's timer does, and checks the drag ends as one undo step.
5. **Acceptance walk.** Written last, from the tests as they stand when the PR is ready.

## Done when

**Tests and CI:**

- [ ] (Core) Every `Command` type in the core is applied by an undo test that checks undo and redo byte for byte, and
  a new command without one fails the audit.
- [ ] (App) Every edit path in the audit table is one undo step; undo restores and redo reproduces the content files
  byte for byte.
- [ ] (App) No editor-only action adds an undo step or changes a content file.
- [ ] (App) While the title or description is being edited, only Undo, Redo, Copy, Paste and Select All among the
  registry's menu items are enabled, including Zoom In, Zoom Out, Actual Size and Toggle Sidebar, and with a bare-key
  override; with the canvas focused they are enabled again.
- [ ] (App) On the 500-region screen, moving one region, moving all 500, resizing a container and drawing a region
  each stay under 16 ms per drag frame on CI, and the times are recorded here.
- [ ] `docs/acceptance.md` maps every spec Section 13 criterion to tests or a Mac check.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Walk the "On the Mac" column of `docs/acceptance.md` on a fresh build.
- [ ] Open a region, type in its title and press Cmd + and Ctrl-Cmd-S: nothing zooms and the sidebar stays put.
  Press Escape, then Cmd +: the canvas zooms.
- [ ] Debug > New 500-Region Document: select all with Cmd-A and drag; the regions follow the pointer smoothly.

## Recorded times

Per-frame times on the CI runner (macos-14), from the `Canvas, 500 regions` lines of the test log:

| Gesture | ms per frame |
| --- | --- |
| Move one region | filled in from CI |
| Move all 500 | filled in from CI |
| Resize a container | filled in from CI |
| Draw a region | filled in from CI |

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Should Zoom and Toggle Sidebar work while typing, as many Mac apps allow? | No. Spec 6.3 and 9 disable every keybind but the standard editing ones while a field is edited. | |
| Should zoom or scrolling alone mark the document edited? | No, as milestone 4 decided. | |
