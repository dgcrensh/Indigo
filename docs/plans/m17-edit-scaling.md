# Edits that cost what they change (milestone 17)

How milestone 17 of the [v1 roadmap](../v1-roadmap.md) is built, the first of the core responsiveness milestones.
Builds on the parenting rule and commands from [m2-commands.md](m2-commands.md), scrolling from
[m9-scrolling.md](m9-scrolling.md), and the core timings `scripts/bench.sh` added after
[m16-chrome-responsiveness.md](m16-chrome-responsiveness.md).

**Status:** shipped

## Goal

Afterwards nudging or dragging a large selection, pasting many regions and shrinking a container keep up with the
keys and the pointer, even on screens with thousands of regions, and a single move does a fraction of today's work.

Measured on `main` (5c62402), release build, Linux cloud VM, per perform and undo:

| Operation | 500 regions | 2,000 | 5,000 |
| --- | ---: | ---: | ---: |
| Select all, move | 24 ms | 365 ms | 2,326 ms |
| Resize a container so its 5 rows fall out | 10 ms | 23 ms | 76 ms |
| Move one region | 2.2 ms | 11 ms | 37 ms |
| Parent for a frame (one call) | 0.6 ms | 2.7 ms | 8.8 ms |

Three causes, in order of cost:

1. `MoveRegions`, `ResizeRegion`, `PasteRegions` and `SetRegionScroll` call `Parenting.place` once per moved, shed
   or pasted region, and every call builds a new `ScrollLayout` (which builds a `RegionIndex`), then another
   `RegionIndex` in `reparentAfterChange` and a third in `attach`. k regions cost k layouts of the whole screen.
2. `Parenting.placement` calls `RegionIndex.isDescendant` for every region on the screen, and that builds the path
   to the root with `insert(at: 0)`: about 980 allocations per single move at 500 regions, the top allocation
   site in heaptrack. Every lookup also hashes a 36-character UUID string.
3. Every region command snapshots the whole screen for undo (`RegionLayout(screen:)`: three dictionaries over
   every region), and the inverse snapshots it again on each undo and redo. It is 25 % of a single move, and it
   walks `Screen.allRegions`, which concatenates arrays at every level of the tree.

## Scope

**In:**

- **An index stored in draw order.** `RegionIndex` keeps its entries in an array in depth-first draw order, one
  `[RegionID: Int]` map from ID to position, and each entry's subtree end. `isDescendant` becomes a range check.
  `ScrollLayout` keeps its entries in an array beside the index's instead of a second dictionary, and walks by
  position. `Region.subtree` and `Screen.allRegions` append into one array in one pass.
- **One layout per command.** `Parenting` places a list of regions against one `ScrollLayout`, rebuilding it only
  after a placement actually changed the tree. Every command that places regions uses it. Results are identical to
  today's, region for region, including order among siblings and frames under scroll offsets.
- **Undo records what changed.** Region commands record the frames and sibling lists they are about to change,
  and their inverse restores exactly those, instead of snapshotting the screen.
- **Timings.** `CorePerformanceTests` gains the operations in the table above at 500 regions, and a 5,000-region
  select-all move, so `scripts/bench.sh` shows the before and after.

**Out:**

- Autosave cost (encoding every screen on each save): [m18-autosave-cost.md](m18-autosave-cost.md).
- Numbering regions with an `Int` throughout the model, or changing `RegionID`'s storage: the array index above
  removes most string hashing from the hot paths. Measure after this milestone before going further.
- Any change to the canvas, `CanvasView.reload()` or the app's undo bridging. The app calls the same commands and
  gets the same inverses.
- Any change to the parenting rule itself, the file format or the example project.
- Faster reading, Markdown export or thumbnails: one-off actions, linear today.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Index and layout in draw order | `Model/RegionIndex.swift`, `Layout/ScrollLayout.swift`, `Model/Region.swift`, `Model/Screen.swift`, `Editing/EditingActions.swift`, `Commands/RegionCommands.swift` | none |
| 2 | Reference implementation and equivalence tests | `Tests/DescriberCoreTests/Support/`, `Tests/DescriberCoreTests/ParentingEquivalenceTests.swift` | none |
| 3 | One layout per command | `Layout/Parenting.swift`, `Commands/RegionCommands.swift` | 1, 2 |
| 4 | Undo records what changed | `Commands/Snapshots.swift`, `Commands/RegionCommands.swift`, `Layout/Parenting.swift` | 3 |
| 5 | Timings | `Tests/DescriberCoreTests/CorePerformanceTests.swift`, `Model/StressProject.swift` | none |

All paths are under `Packages/DescriberCore/Sources/DescriberCore/` or `Packages/DescriberCore/Tests/` unless they
start with `Tests/`. Steps 1, 2 and 5 can be built in parallel. Land step 5 first in the branch so every later
step can be timed against `main`.

1. **Index and layout in draw order.** `RegionIndex.Entry` gains `subtreeEnd`, the draw order of its last
   descendant (its own draw order for a leaf). Entries live in an array indexed by draw order; `entries[id]`
   becomes a lookup in a `[RegionID: Int]` map, reserved to the region count up front. `isDescendant(_:of:)`
   checks `ancestor.drawOrder <= id.drawOrder <= ancestor.subtreeEnd`. `path(to:)` appends and reverses. Add
   `isInside(_:anyOf:)` (walks parents without building an array) and use it in `topmostRegions` and
   `DeleteConfirmation.message`, which today build a path per selected region. `ScrollLayout` stores its entries
   in an array with the same positions as `index.regions` and walks `index.regions` by position in
   `region(at:)`, `regions(touching:)` and `scrollTarget`, so a walk does no hashing. `Parenting.placement` walks
   by position, skips the excluded subtree as one range, and reads the drawn content area from the array.
   `Region.subtree` and `Screen.allRegions` fill one array with an explicit stack. The public API of both types
   stays as it is; the app compiles unchanged. Covered by the existing `ParentingTests`, `HitTestingTests`,
   `ScrollingTests` and `CommandTests`, plus a test that `isDescendant` agrees with the path-based answer for
   every pair on the stress screen.
2. **Reference implementation and equivalence tests.** Copy today's `Parenting.place`, `reparentAfterChange`,
   `replaceChildrenOutsideContent` and the four commands' `apply` into test support as `ReferenceCommands`, which
   rebuild everything per region exactly as `main` does. A seeded generator builds random screens of 50 to 300
   regions with nesting up to five deep, overlapping and equal-size siblings, and some scrolling regions with
   saved offsets. `ParentingEquivalenceTests` runs at least 200 seeds per command and checks that the new and
   reference versions leave identical trees (IDs, parents, sibling order, frames) for: moving a random selection
   (including parents and children together, and hidden regions under scroll), resizing so children fall out,
   pasting several regions with and without a parent, and turning scrolling off. A failure prints the seed.
3. **One layout per command.** Add `Parenting.place(_ ids: [RegionID], in:offsets:keepingParents:)`, which builds
   one `ScrollLayout`, places each region in the order given, and rebuilds the layout only when a placement
   changed a parent (detach and attach) or a frame. A region that keeps its parent keeps its frame, since its
   file frame is its drawn frame plus its parent's content shift, so the layout stays valid and the common case
   (a nudge inside the same parent) builds one layout for the whole command. After each region, children that
   no longer fit its content area are placed the same way, as `reparentAfterChange` does today; that check reads
   file frames and needs no layout. `attach` takes the index it already has instead of building one.
   `MoveRegions`, `ResizeRegion`, `PasteRegions` and `SetRegionScroll` use it. `PasteRegions` still attaches and
   places each copy in the given order, as today; a copy attached at the top level lands at the end of the draw
   order with no shift or clip, so the layout appends its subtree's entries in place instead of rebuilding. `CreateRegion` keeps its single placement. Done when step 2's tests pass
   unchanged.
4. **Undo records what changed.** Replace the whole-screen `RegionLayout` with a `LayoutChanges` record: the
   original sibling list of each parent (or the top level) whose children a command is about to change, and the
   original frame of each region it is about to move, each recorded once, before its first change, keyed by
   `ObjectIdentifier` of the `Region`. `Parenting.detach`, `attach` and `place` take the record and write to it
   before they change anything; commands record frame changes they make themselves (`MoveRegions` offsetting
   subtrees, `ResizeRegion` setting the frame, `ReorderRegion(s)` and `DeleteRegions` changing sibling lists).
   `RestoreLayout.apply` records the current value of the same lists and frames, then restores the recorded
   ones, so undo and redo stay symmetric and keep region identity. Covered by the existing undo tests
   (`testEveryRegionCommandUndoesAndRedoesToTheSameBytes`, `testUndoKeepsRegionIdentity`) and a new seeded test:
   20 random region commands on a random screen, then undo all (the package bytes equal the start), then redo all
   (they equal the end), for at least 100 seeds.
5. **Timings.** `CorePerformanceTests` adds: select-all move (perform and undo), resizing a container so its rows
   fall out, pasting a copy of 24 containers, and a select-all move on a 5,000-region stress project, each printed
   like the existing lines. Budgets stay loose (50 ms at 500 regions, 1,500 ms at 5,000) so a slow runner or a debug
   build doesn't fail them; the targets below are read from the printed times.

## Done when

**Tests and CI:**

- [ ] `ParentingEquivalenceTests` pass for every command and seed: the new placement leaves the same trees as the
  reference copy of `main`'s.
- [ ] The seeded undo and redo round trip passes, and every existing `CommandTests` and `ParentingTests` test passes
  unchanged.
- [ ] `isDescendant` agrees with the path-based answer for every pair of regions on the 500-region stress screen.
- [ ] `scripts/bench.sh` in a cloud session prints, at 500 regions: select-all move under 4 ms (from 24), move one
  region under 1 ms (from 2.2), resize shedding 5 rows under 2 ms (from 10), parent for a frame under 0.3 ms (from
  0.6); and a 5,000-region select-all move under 100 ms (from 2,326). The PR reports the before and after.
- [ ] `scripts/bench.sh --profile` no longer shows `RegionIndex.path(to:)` or `RegionLayout.init(screen:)` among the
  hottest functions.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes (the PR says which stages ran).

**On the Mac:**

- [ ] On the 500-region stress project, Cmd-A then holding an arrow key moves everything smoothly, and Cmd-Z puts it
  back in one step.
- [ ] Dragging a container out of and back into a scrolled region re-parents it as before.
- [ ] Duplicating a selection of 20 regions and undoing it is instant.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Keep the reference copy of today's commands in the tests for good, or delete it once this ships? | Keep it: it is the cheapest guard on the parenting rule for later changes. | Dallas agreed: the default. |
| Rebuild the layout after a parent change, or update it in place? | Rebuild. In-place updates renumber everything drawn after the new parent, which costs about as much and is harder to get right; revisit if paste timings miss. | Dallas agreed: the default. |
