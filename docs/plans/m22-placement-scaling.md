# Placing many regions, and finding one, without scanning everything (milestone 22)

How milestone 22 of the [v1 roadmap](../v1-roadmap.md) is built, a core milestone. Builds on the one-layout-per-command
placement from [m17-edit-scaling.md](m17-edit-scaling.md). From the profile in `real-hardware-profile.md` in the
project files (items 3 and 5). Independent of milestones 20 and 21.

**Status:** draft

## Goal

Afterwards nudging, dragging or pasting thousands of regions keeps up with the keys, and typing in the details panel
costs the same on the last screen of a large project as on the first.

Milestone 17 made a multi-region move cost one layout per command, but each moved root still scans every region on
the screen for a parent, and each check reads the region's content area through its class. Measured on screen,
Release, MacBook Air M1:

| Per action | 500 regions | 2,000 | 5,000 |
| --- | ---: | ---: | ---: |
| Nudge everything | 2.5 ms | 4.7 ms (p95 12.5) | 21 ms |
| Drop a drag of everything | 5.4 ms | 24.8 ms | 72 ms |

In the 5,000-region nudge profile, `Parenting.placement` is 47 % of the time, and `ScrollLayout.drawnContentArea(at:)`
with `Region.contentArea` is 31 % on its own.

Separately, `Project.region(withID:)` (`Commands/Command.swift`) builds a whole `RegionIndex` for each screen in turn
until it finds the region. The details panel goes through it on every keystroke, so on the last of 40 × 300-region
screens a keystroke costs 5.1 ms instead of 1.0 ms on the first.

## Scope

**In:**

- **Content areas stored with the layout.** `ScrollLayout` computes each region's drawn content area and frame area
  once, when it is built, into a plain array of values in draw order, and `Parenting.placement` reads that array.
  The walk then touches no class instance until it has a candidate.
- **Candidates found by position.** A `ScrollLayout` built for placement also keeps a coarse grid over the screen
  (cells of 256 pt): each cell lists, in draw order, the regions whose drawn content area overlaps it. A placement
  reads only the cells the frame touches and checks those regions, then applies the same tie-break as today. When a
  placement changes the tree, the placer rebuilds the layout as it does now.
- **Finding a region without building indexes.** `Project.region(withID:)` walks each screen's tree and stops at the
  match, building nothing. A new `Project.region(withID:onScreen:)` checks the given screen first; `RegionEditor` and
  the details panel, which know the screen, use it. Commands that carry only a region ID (`SetRegionValue`,
  `SetRegionScroll`) keep calling `region(withID:)`, which is now cheap.

**Out:**

- Changing the parenting rule, tie-breaks or the order regions are placed in. Every outcome stays identical.
- The canvas reload after a large move (34 % of the 5,000-region nudge): milestone 20 makes it cost what is mounted.
- Keying indexes by integer instead of UUID string (`core-hotspots.md` item 5): not needed once the scans are gone.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Content areas in the layout | `Layout/ScrollLayout.swift`, `Layout/Parenting.swift` | none |
| 2 | Grid of candidates | `Layout/ScrollLayout.swift`, `Layout/Parenting.swift` | 1 |
| 3 | Region lookup | `Commands/Command.swift`, `Editing/RegionEditor.swift`, `InterfaceDescriber/DetailsPanelController.swift` | none |
| 4 | Benchmarks and timings | `Tests/.../CorePerformanceTests.swift`, `scripts/bench.sh` | 2, 3 |

1. **Content areas in the layout.** `ScrollLayout.Entry` gains `drawnContent: Frame` and `area: Int`, filled when the
   layout is built. `drawnContentArea(at:)` returns the stored value; `placement` reads `drawnContent`, `drawn` and
   `area` from the entry, and the region's `scroll` and `id` only for a region whose content area contains the frame.
2. **Grid of candidates.** `ScrollLayout` builds a `PlacementGrid` lazily on first use by `placement`, so layouts
   used only for drawing don't pay for it. A frame's candidates are the union of its cells' lists, merged in draw
   order, with the excluded subtree skipped by draw-order range as today. The randomized reference check from
   milestone 17 (`ParentingEquivalenceTests`) runs with the grid and must agree on
   every screen; add a case with regions larger than a cell, regions outside the canvas bounds and negative
   coordinates.
3. **Region lookup.** `Project.region(withID:)` becomes a depth-first walk with early exit over each screen's regions.
   `region(withID:onScreen:)` looks on that screen first and falls back to the walk. `RegionEditor.regionExists` and
   `DetailsPanelController`'s frame lookup use the screen they have. Tests: a region on the
   last screen is found, a region whose screen hint is wrong is still found, a missing one returns nil.
4. **Benchmarks and timings.** `CorePerformanceTests` adds nudge-all and drop-drag-all timings at 2,000 and 5,000
   regions, and a region lookup on the last of 40 screens. `OnScreenPerformanceTests` (milestone 20), if it has
   landed, reports nudge-all on screen.

## Done when

**Tests and CI:**

- [ ] `ParentingEquivalenceTests` passes with the grid on random screens, plus the new edge cases.
- [ ] Every `ParentingTests` and `CommandTests` test passes unchanged.
- [ ] The lookup tests in step 3 pass.
- [ ] `CorePerformanceTests` prints the new timings; the PR reports before and after.
- [ ] `scripts/check.sh` passes (the PR says which stages ran).

**On the Mac (MacBook Air M1, Release):**

- [ ] On the 5,000-region project, select all and hold an arrow key: each nudge is under 8 ms and the selection
  keeps up with the key repeat.
- [ ] Dropping a drag of all 5,000 regions takes under 25 ms.
- [ ] On a 40-screen project, typing a title on the last screen feels the same as on the first (under 1.5 ms per
  keystroke in the timings).
- [ ] Moving regions in and out of containers and scrolling regions re-parents them exactly as before.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Cell size of the candidate grid? | 256 pt, about one container in the stress project. Tune from the benchmark. | |
