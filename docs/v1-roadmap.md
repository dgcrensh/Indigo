# Interface Describer: v1 Roadmap

**Spec:** [app-spec.md](app-spec.md) (Revision 2)
**Scope:** Everything in spec Section 13 (Acceptance Criteria). Nothing in Section 14 (Out of Scope) or Section 15 (Roadmap).

This roadmap splits v1 into milestones. Each milestone gets its own plan in [plans/](plans/), written from
[plan-template.md](plan-template.md) and reviewed before it is built (plan, review, build). One plan is one PR.
Plans are written a milestone or two ahead of the build, so later plans can use what earlier ones taught.

---

## 1. Milestones

| # | Milestone | Plan | Builds on | Status |
| --- | --- | --- | --- | --- |
| 0 | Scaffold: package, app target, CI, `CLAUDE.md`, `scripts/check.sh` | [m0-scaffold.md](plans/m0-scaffold.md) | none | shipped |
| 1 | Data model and file format | [m1-file-format.md](plans/m1-file-format.md) | 0 | shipped |
| 2 | Command layer, parenting, snapping | [m2-commands.md](plans/m2-commands.md) | 1 | shipped |
| 3 | Document and app shell | [m3-document-shell.md](plans/m3-document-shell.md) | 1, 2 | shipped |
| 4 | Canvas rendering (starts with a 500-region performance spike) | [m4-canvas-rendering.md](plans/m4-canvas-rendering.md) | 3 | shipped |
| 5 | Tools, gestures, toasts, keybind registry | [m5-tools-gestures.md](plans/m5-tools-gestures.md) | 4 | shipped |
| 6 | Details panel | [m6-details-panel.md](plans/m6-details-panel.md) | 5 | shipped |
| 7 | Selection and editing | [m7-selection-editing.md](plans/m7-selection-editing.md) | 5 | shipped |
| 8 | Screens, viewports, variants, links | [m8-screens-links.md](plans/m8-screens-links.md) | 3 (link following needs 5) | shipped |
| 9 | Scrolling | [m9-scrolling.md](plans/m9-scrolling.md) | 5, 6 | shipped |
| 10 | Settings file and live reload | [m10-settings.md](plans/m10-settings.md) | 3 | shipped |
| 11 | Exports: Markdown, single-file JSON, PNG | [m11-exports.md](plans/m11-exports.md) | 1 (PNG needs 4) | shipped |
| 12 | Hardening and acceptance pass | [m12-hardening.md](plans/m12-hardening.md) | all | shipped |
| 13 | Paper look: palette, canvas, tool pill, details card | [m13-paper-look.md](plans/m13-paper-look.md) | 12 | shipped |
| 14 | Paper chrome: sidebar cards, title bar, app icon | [m14-paper-chrome.md](plans/m14-paper-chrome.md) | 13 | shipped |
| 15 | Canvas responsiveness: edits and pinch | [m15-canvas-responsiveness.md](plans/m15-canvas-responsiveness.md) | 4, 12 | shipped |
| 16 | Sidebar and zoom animation responsiveness | [m16-chrome-responsiveness.md](plans/m16-chrome-responsiveness.md) | 15 | shipped |
| 17 | Edits that cost what they change: multi-region moves, paste, undo snapshots | [m17-edit-scaling.md](plans/m17-edit-scaling.md) | 2, 9 | draft |
| 18 | Autosave that writes what changed | [m18-autosave-cost.md](plans/m18-autosave-cost.md) | 1, 3 | draft |

Milestones 0 → 1 → 2 → 3 are the critical path. After that, two tracks can run at the same time:

- **Canvas track:** 4 → 5 → 6 → 7 → 9
- **Project track:** 8, 10, and the Markdown and JSON parts of 11

### Milestone scope at a glance

- **3. Document and app shell.** `NSDocument` reading and writing the package through `FileWrapper`, autosave,
  Revert, Save As, recent documents. Window with a canvas placeholder, the collapsible sidebar (hidden by
  default, Ctrl-Cmd-S), a right-hand panel slot, and a menu bar skeleton.
- **4. Canvas rendering.** Viewport frame, regions with truncated titles, marking of parts outside the frame,
  light grid while snapping or adjusting, pan, pinch and Cmd +/−/0 zoom, zoom and pan kept in editor state.
- **5. Tools and gestures.** Select, Region and Write tools as in spec Section 5; move, resize handles, marquee,
  Shift-click, snapping and Option inversion, minimum size, toasts, the `G` grid popover, `KeybindRegistry`
  with the spec Section 9 defaults.
- **6. Details panel.** The SwiftUI form in spec Section 6, the slide-in and zoom-to-fit animation, Return, Tab
  and Escape behaviour, blank-title rules, keybind suspension while editing text, switching regions.
- **7. Selection and editing.** Everything in spec Section 7, plus showing descriptions on the canvas with `D`
  and `Shift-D` (spec Sections 4 and 9), since `D` acts on the selection.
- **8. Screens, viewports, variants, links.** Everything in spec Section 8.
- **9. Scrolling.** Scroll settings, drawing the content area, scroll-in-region, clipping, parenting against the
  content area.
- **10. Settings.** `settings.json` with directory watching, an error banner on a bad file, live keybind
  overrides, user presets.
- **11. Exports.** Markdown and single-file JSON in the core with golden tests; PNG at 1× and 2× from the canvas
  renderer.
- **12. Hardening.** Undo audit, keybind-suppression audit, 500-region performance check, and a walk of the
  full spec Section 13 list.
- **13 and 14. Paper studio.** The app's own look, after the v1 acceptance pass: a warm paper desk with the screen
  as a rounded sheet, regions tinted by kind family, a fixed indigo accent, a night paper dark mode, a clickable
  tool pill, the details panel and sidebar as cards, screen thumbnails, and an app icon. Chosen from three mocked
  directions in the project thread; 13 is the canvas and panel, 14 the window chrome.
- **17 and 18. Core responsiveness.** From the perf profile of the core in a cloud session
  (`scripts/bench.sh --profile`). 17 makes moving, pasting and shrinking many regions cost one layout per command
  instead of one per region, and records undo for what changed rather than the whole screen; 18 skips writing
  unchanged screens on autosave and speeds up the JSON writer. Independent of each other.

---

## 2. Decisions Every Plan Assumes

These close the open items in spec Sections 12 and 16. Each is a default and can be changed before the
milestone that depends on it. Answers go here and in the affected plan.

| # | Question | Default | Needed by |
| --- | --- | --- | --- |
| D1 | Architecture (spec 12) | The spec's recommendation: AppKit canvas, SwiftUI panels hosted in AppKit, `NSDocument` + `FileWrapper`, `@Observable` model, command layer over `NSUndoManager`. | 0 |
| D2 | Blank fields (spec 16.1) | As the spec reads it: a new region with a blank title is discarded, a cleared title on an existing region reverts, a blank description is allowed. | 6 |
| D3 | PNG renders in the package (spec 16.3) | No. PNGs are export-only in v1. | 11 |
| D4 | Per-link presentation override (spec 16.4) | No. The target screen's kind decides; the free-text `trigger` can note exceptions. | 8 |
| D5 | Name and extension (spec 16.5) | Keep the placeholders behind one constant each, so a rename is a one-line change plus the UTI declaration. | 0 |
| D6 | Xcode project | Generated by XcodeGen from `project.yml`; `.xcodeproj` is gitignored, so there are no project-file merge conflicts. | 0 |

---

## 3. Architecture

The app is two layers:

1. **`DescriberCore`**, a Swift package with no UI. It owns the data model, the JSON format, the package
   reader and writer, the command layer (every edit and its inverse), the parenting rule, snapping math, and
   the Markdown and single-file JSON exports. Most of the spec's rules live here, tested with `swift test`.
2. **The macOS app** (`InterfaceDescriber/`), a thin layer that hosts the AppKit canvas and SwiftUI panels
   on top of the core. It owns rendering, gestures, tools, keybinds, the details panel, the sidebar, settings
   file watching, and PNG export.

The core uses Foundation only (no AppKit, no `FileWrapper`), and reads and writes the package as an in-memory
tree of files. The app converts that tree to and from `FileWrapper`. Keeping the core portable means a cloud
session can run its tests on Linux with a Swift toolchain, and a future agent CLI or MCP server (spec Roadmap)
can depend on it.

```
Indigo/
  CLAUDE.md                       Conventions for agents building this repo
  project.yml                     XcodeGen definition
  scripts/check.sh                Core tests, format check, app build and tests
  Packages/DescriberCore/         The core package and its tests
  InterfaceDescriber/             The app target
  Schema/                         JSON Schema for the package format, with an example project
  docs/                           Spec, roadmap, plan template, plans/
  .github/workflows/ci.yml        Runs scripts/check.sh on a macOS runner
```

---

## 4. Acceptance Criteria Map

Every spec Section 13 criterion, and the milestone whose "Done when" list proves it. [acceptance.md](acceptance.md)
names the tests behind each one and the check left for the Mac.

| Spec 13 criterion | Milestone |
| --- | --- |
| `V`/`R`/`W` switch tools with a toast | 5 |
| Region tool draws anywhere; parenting assigns the parent | 2, 5 |
| Move and resize, snapping, `S`, Option inverts | 2, 5 |
| `G` grid slider; grid never moves regions | 5 |
| Moving a parent moves children; drag in or out re-parents | 2, 5 |
| Marquee, Shift-click, multi move and delete, `Shift-Return` | 5, 7 |
| Minimum 4 × 4 pt | 2 |
| Drawing opens the panel, title focused, zoom-to-fit | 6 |
| Return to description, Escape commits and restores zoom | 6 |
| Blank-title new region discarded | 6 |
| Kind, links, scrolling set in the panel | 6, 9 |
| Screen create, rename, reorder, duplicate, delete, kind, viewports | 8 |
| Variant groups | 8 |
| Follow links, Back/Forward | 8 |
| Scroll a region to place children in hidden content | 9 |
| `.uidesc` package, one file per screen, identical reopen, autosave | 1, 3 |
| Fixed key order, empty optionals omitted | 1 |
| Different `schemaVersion` refuses to open | 1, 3 |
| PNG, Markdown, single-file JSON exports | 11 |
| Settings and user presets persist across relaunch | 8, 10 |
| Hand edits to settings apply live; an invalid file changes nothing | 10 |
| Undo and redo for every change; a drag and a field session are one step each | 2, 5, 6, 12 |
| No canvas keybind fires while editing text | 6, 12 |
| Smooth with 500 regions | 4, 12 |

---

## 5. Risks

| Risk | Mitigation |
| --- | --- |
| Core Graphics drawing can't stay smooth at 500 regions | Milestone 4 starts with a spike on a 500-region fixture, before tools are built on the renderer. Fallback is one `CALayer` per region. |
| Scroll-in-region versus canvas pan feels wrong | Isolated in milestone 9 with its own check on the Mac; gesture routing lives in one place. |
| Undo grouping drifts as features are added | All edits go through commands; tests assert undo-stack depth after gestures; milestone 12 audits it. |
| Key order or formatting changes silently | The example project must re-save byte for byte on every `scripts/check.sh` run. |
| Autosave is slow or loses files | Only changed screen files are rewritten; rename and delete paths are tested in milestone 1. |
| Settings watcher misses editors that save by replacing the file | Watch the directory, not the file; test with an atomic replace in milestone 10. |
