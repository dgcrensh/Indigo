# Autosave that skips screens nobody touched (milestone 23)

How milestone 23 of the [v1 roadmap](../v1-roadmap.md) is built, a core milestone. Builds on the encoding cache from
[m18-autosave-cost.md](m18-autosave-cost.md) and the command layer from [m2-commands.md](m2-commands.md). From the
profile in `real-hardware-profile.md` in the project files (item 6). Independent of milestones 20 to 22.

**Status:** draft

## Goal

Afterwards an autosave after an edit costs about what it takes to encode the screens that edit touched, however many
other screens the project has.

Milestone 18 reuses the text of unchanged files, but still builds every screen's `JSONValue` tree and compares it
with the cached one (`JSONValue.isIdentical`) to find out that it is unchanged. Its open question chose that over
dirty tracking unless large projects still hitch. Measured on the Mac (MacBook Air M1, Release), an autosave after
one nudge on a 40-screen project of 300 regions each costs 6.3 ms median and 38 ms worst on the main thread; comparing
trees is 35 % of that and encoding screens 17 %.

## Scope

**In:**

- **Commands say which screens they touch.** `Command` gains `affectedScreens: AffectedScreens`, either
  `.screens(Set<ScreenID>)` or `.all`, as a requirement with no default, so the compiler makes every command,
  including future ones, say which. Region commands name their screen; `CompositeCommand` takes the union; screen commands that only change one
  screen's own fields (kind, viewport, scrolling) name it; anything that renames, adds, removes, reorders or groups
  screens says `.all`, since a screen's file names other screens in its links.
- **The session counts changes per screen.** `EditSession` keeps a generation number for the project and one per
  screen. Every applied change (perform, undo, redo, `applyWithoutRecording`) bumps the project generation, and either
  the named screens' generations or, for `.all`, a separate "every screen" generation.
- **The write skips untouched screens before encoding.** `ProjectPackage.write` takes an optional
  `generations: PackageGenerations` from the session. The cache remembers, per screen file, the generations it was
  encoded at; a screen whose own and "every screen" generations match, and whose cached data still equals the
  previous tree's, reuses the previous data without building its value. Without generations, the write behaves
  exactly as now. The manifest and editor state are always built, as they are small.

**Out:**

- Encoding on a background thread (`canAsynchronouslyWrite`). With the skip, a typical autosave is one screen's
  encode; revisit only if a single very large screen still hitches.
- Any change to the file format or its bytes.
- Tracking editor-state changes per screen: the editor state is one small file, built every time.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Affected screens on commands | `Commands/Command.swift`, `RegionCommands.swift`, `ScreenCommands.swift`, `Snapshots.swift` | none |
| 2 | Generations in the session | `Commands/EditSession.swift` | 1 |
| 3 | Skipping in the write | `Format/ProjectPackage.swift`, `InterfaceDescriber/Document.swift` | 2 |
| 4 | Equivalence test and benchmarks | `Tests/.../ProjectPackageTests.swift`, `CorePerformanceTests.swift` | 3 |

1. **Affected screens on commands.** Add `AffectedScreens` and the protocol requirement. Fill it in for every region command (they all carry a `screen`), for `RestoreLayout` and the snapshot commands, and for
   screen commands that change only that screen. Commands that find their region by ID alone (`SetRegionValue`,
   `SetRegionScroll`) record the screen they found when applied, and their inverse carries it. Tests: each region
   command and its inverse name the screen it changed; screen renames, adds, deletes and reorders say `.all`.
2. **Generations in the session.** `EditSession.generations` returns the current `PackageGenerations` (project,
   every-screen, per-screen). Applied commands bump them as described, reading the affected screens from the
   inverse that `apply` returned, since an ID-only command learns its screen only when applied (a forward command
   with no screen yet says `.all` until then). A failed command bumps nothing.
3. **Skipping in the write.** `write(project:previous:cache:generations:)`; `PackageEncodingCache` stores the
   generations per path. `Document.fileWrapper(ofType:)` passes `model.session.generations`. A new session (read,
   revert, replace) starts a new cache, as today.
4. **Equivalence test and benchmarks.** A seeded test applies random commands (region edits, screen renames, reorders,
   adds, deletes, undo and redo, and details-panel style `applyWithoutRecording`) to a multi-screen project and,
   after each, checks that a write with the long-lived cache and generations equals an uncached write byte for byte.
   `CorePerformanceTests` times a write after one nudge on the 40 × 300 project, with and without generations.

## Done when

**Tests and CI:**

- [ ] The affected-screens tests in step 1 and the seeded equivalence test in step 4 pass.
- [ ] Every existing `ProjectPackageTests` test passes, and `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `CorePerformanceTests` prints the write timings; with generations, a write after one nudge on the 40 × 300
  project is under a fifth of the write without them. The PR reports both.
- [ ] `scripts/check.sh` passes (the PR says which stages ran).

**On the Mac (MacBook Air M1, Release):**

- [ ] On the 40 × 300 project, an autosave after one edit takes under 1.5 ms on the main thread.
- [ ] Save, close and reopen keeps every edit; renaming a screen that others link to updates the linking screens'
  files.
- [ ] Revert to Saved, then edit and save, writes correctly.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Should screen renames dirty only the screens that link to the renamed one? | No: `.all`. Renames are rare and the full write is what happens today. | |
