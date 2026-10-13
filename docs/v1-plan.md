# Interface Describer: v1 Implementation Plan

**Spec:** [app-spec.md](app-spec.md) (Revision 2)
**Status:** Draft for review
**Scope:** Everything in spec Section 13 (Acceptance Criteria). Nothing in Section 14 (Out of Scope) or Section 15 (Roadmap).

---

## 1. Summary

The app is built in two layers:

1. **`DescriberCore`**, a Swift package with no UI. It owns the data model, the JSON format, the package reader and writer, the command layer (every edit, with its inverse), the parenting rule, snapping math, and the Markdown and single-file JSON exports. It is tested with `swift test` and is where most of the spec's rules live.
2. **The macOS app**, which hosts an AppKit canvas and SwiftUI panels on top of the core. It owns rendering, gestures, tools, keybinds, the details panel, the sidebar, settings, and PNG export.

Work is split into 12 milestones. Each one ends in something that runs and is tested, and each maps to specific acceptance criteria (Section 7). The format and command layer come first because every later milestone depends on them and they are the cheapest place to get rules right.

---

## 2. Decisions This Plan Assumes

These close the open items in spec Sections 12 and 16. Each is a default; any of them can be changed before the milestone that depends on it.

| # | Question | Default taken | Needed by |
|---|---|---|---|
| D1 | Architecture (spec 12) | Adopt the spec's recommendation: AppKit canvas, SwiftUI panels hosted in AppKit, `NSDocument` + `FileWrapper`, `@Observable` model, command layer over `NSUndoManager`. | M0 |
| D2 | Blank fields (16.1) | As the spec reads it: a new region with a blank title is discarded, a cleared title on an existing region reverts, a blank description is allowed. | M6 |
| D3 | PNG renders in the package (16.3) | No. PNGs are export-only in v1. Easy to add later as a save hook once PNG export exists. | M11 |
| D4 | Per-link presentation override (16.4) | No. Presentation comes from the target screen's kind; the free-text `trigger` can note exceptions. | M8 |
| D5 | Name and extension (16.5) | Keep the placeholders (`Interface Describer`, `.uidesc`) behind a single constant each, so a rename is a one-line change plus the UTI declaration. | M0 |
| D6 | Project generation | Use XcodeGen (`project.yml`) so the Xcode project is generated, not hand-merged. Agents and humans edit YAML; `.xcodeproj` is gitignored. | M0 |
| D7 | Screen file slug collisions | Spec doesn't say. Two screens that slug the same get `-2`, `-3`, and so on, in sidebar order. | M1 |
| D8 | ID format | Lowercase UUID strings. | M1 |
| D9 | JSON formatting | 2-space indent, `"key": value`, one key per line, arrays of objects one element per line, trailing newline. Whole-point numbers written as integers. | M1 |

---

## 3. Repository Layout

```
Indigo/
  docs/
    app-spec.md
    v1-plan.md
  project.yml                     XcodeGen definition (app target, test target)
  Packages/
    DescriberCore/
      Package.swift
      Sources/DescriberCore/
        Model/                    Project, Screen, Region, Link, Viewport, Scroll, kinds
        Format/                   OrderedJSONWriter, decoding, ProjectPackage (FileWrapper I/O), EditorState
        Commands/                 Command protocol, region/screen/link commands, UndoStack bridge
        Layout/                   Parenting rule, snapping, hit-test geometry
        Export/                   MarkdownExporter, SingleFileJSONExporter
        Settings/                 AppSettings model and parsing (no file watching)
      Tests/DescriberCoreTests/
        Fixtures/                 Golden .uidesc packages and expected exports
  App/
    Sources/
      AppDelegate, Document/      NSDocument subclass, window controller
      Canvas/                     CanvasView (AppKit), renderer, tools, gestures, toasts
      Panels/                     Details panel, sidebar, grid popover (SwiftUI)
      Keybinds/                   KeybindRegistry, menu construction
      Settings/                   SettingsStore (file watching, error surfacing)
      Export/                     PNG export
    Resources/                    Info.plist (document type, UTI), assets
    Tests/                        App-level tests (canvas math, keybind suppression, UI tests)
  .github/workflows/ci.yml        swift test + xcodebuild test on macOS
```

Keeping the core in a package means most tests run without launching the app, and a future CLI or MCP server (spec Roadmap) can depend on the same package.

---

## 4. Cross-Cutting Design

### 4.1 Model
- `Project` (`@Observable`): name, ordered screen list, variant groups.
- `Screen` (`@Observable`): id, name, kind, viewport, optional scroll, root region list.
- `Region`: id, title, optional kind, frame (`x, y, w, h` as `Int` points, absolute), description, optional scroll, links, children. Regions are reference types so the canvas can hold stable identity, with an id-to-region index per screen for O(1) lookup.
- `EditorState`: per-screen zoom, pan, grid size, scroll offsets; per-region description visibility; last active screen. Lives beside the model, never in screen files.

### 4.2 File format
- **Writing:** a small `OrderedJSONWriter` that emits keys in the exact spec order (`id, title, kind, x, y, w, h, description, scroll, linksTo, children` and `id, name, kind, viewport, scroll, regions`). `JSONEncoder` can't guarantee custom key order, so we don't use it for output.
- **Omission:** empty `children`, empty `linksTo`, nil `scroll`, and `kind: open` are never written.
- **Derived fields:** `screenName` in links and `name`/`file` in the manifest are recomputed on every save and ignored on read.
- **Reading:** `JSONDecoder` into DTOs, then validation (schema version, unknown screen ids in links, missing files) with readable errors.
- **Package I/O:** `ProjectPackage` turns a model into a `FileWrapper` tree and back. On save, only changed screen files are replaced and renamed screens move their file, so autosave stays cheap and git sees renames.
- **Golden tests:** fixture packages are read, written, and compared byte-for-byte. This is the main guard on "fixed key order" and "reopens with identical content".

### 4.3 Commands and undo
- Every change is a `Command` with `apply(to:)` and an inverse. The UI never mutates the model directly.
- Commands register with `NSUndoManager` through a thin bridge, so the core stays testable with a fake undo stack.
- **Grouping:** a drag (move or resize) is applied live as a preview and committed as one command on mouse-up. A details panel field edit is one command per field per panel session, committed on blur or close.
- **Parenting** runs as part of every create, move, and resize command, so re-parenting is undone with the change that caused it.

### 4.4 Parenting rule
Pure function in `Layout/`: given a screen and a region's new frame, return the smallest region whose content area fully contains it (ties go to the one on top; the region and its own descendants are excluded). The content area is the frame, or the scroll content size when the region scrolls. Children of a resized parent that no longer fit are re-parented by the same rule. This gets thorough unit tests because the spec relies on it for drawing, dragging in and out, and resizing.

### 4.5 Canvas
- One layer-backed `NSView` subclass that draws the visible regions with Core Graphics, invalidating only dirty rects. Title text layout is cached per region and rebuilt only on title or size change.
- Hit testing walks the tree top-down in reverse z-order. With 500 regions a linear walk is fine; a spatial index is added only if profiling asks for it.
- A **performance spike runs at the start of M4** with a 500-region fixture. If Core Graphics drawing can't hold 60 fps during pan, zoom, and drag, switch to one `CALayer` per region before building tools on top.
- Toasts, the grid popover, and the details panel are SwiftUI views hosted above or beside the canvas.

### 4.6 Keybinds
- `KeybindRegistry` maps action identifiers to key combinations, with spec Section 9 defaults and overrides from settings.
- The canvas handles keys through the registry. When any text field is first responder, the registry is suspended; only Escape, Tab, and standard Cmd shortcuts reach the window. One test covers each binding to make sure it is ignored while editing.
- The menu bar is built from the same registry, so menus always show the current binding.

### 4.7 Settings
- `~/Library/Application Support/Interface Describer/settings.json`: default viewport, default grid size, snap default, user viewport presets, keybind overrides.
- Watched with a `DispatchSource` on the containing directory, so editors that save by replacing the file are still seen.
- A parse failure keeps the current settings and shows the error in a non-modal banner. The app never rewrites the file except to add a user preset the user created in-app, and that write preserves everything else in the file.

---

## 5. Milestones

Each milestone lists its scope and its exit check. "Done" for a milestone means its tests pass in CI and the exit check has been demonstrated.

### M0. Scaffold
- XcodeGen `project.yml`, app target (macOS 14), `DescriberCore` package, test targets.
- Document type and UTI for `.uidesc` declared as a package.
- GitHub Actions on a macOS runner: `swift test` for the core, `xcodebuild test` for the app.
- `swift-format` config and a lint step.
- **Exit:** an empty app launches, opens an empty window, and CI is green.

### M1. Data model and file format
- Model types, `OrderedJSONWriter`, decoding and validation, `ProjectPackage` read/write, editor state file, slugging and renames.
- `schemaVersion` check with a clear error.
- **Exit:** golden fixture packages round-trip byte-for-byte; a package with a different `schemaVersion` fails with an error; empty optionals are absent from output.

### M2. Command layer, parenting, snapping
- Commands for region create, move, resize, delete (with children), edit title/description/kind/links/scroll, reorder siblings, and screen add/rename/duplicate/reorder/delete/set kind/set viewport.
- Parenting rule and snapping math (grid steps, Option inversion is a parameter, minimum 4 × 4 pt).
- **Exit:** unit tests cover every command's apply and undo, and the parenting cases in spec Section 5 (draw inside, drag in, drag out, resized parent leaves children outside, equal-size tie).

### M3. Document and app shell
- `NSDocument` subclass using `ProjectPackage`, autosave in place, Revert, Save As, recent documents.
- Window with canvas placeholder, collapsible sidebar (hidden by default, Ctrl-Cmd-S), and a right-hand panel slot.
- Menu bar skeleton built from the keybind registry.
- **Exit:** create, save, close, reopen, and autosave a project with screens added through the sidebar.

### M4. Canvas rendering
- Performance spike first (Section 4.5).
- Viewport frame, regions with truncated titles, out-of-frame marking, light grid while snapping or adjusting, pan (two-finger scroll), zoom (pinch, Cmd +/−, Cmd 0), zoom and pan saved in editor state.
- **Exit:** a 500-region fixture pans and zooms smoothly; regions outside the frame are marked.

### M5. Tools and gestures
- Select, Region, and Write tools with the click, drag, and double-click behaviors in spec Section 5.
- Move, resize handles, marquee, Shift-click, snapping and Option inversion, minimum size, toasts for tool, snap, and grid changes, grid popover (`G`) with fixed steps.
- `KeybindRegistry` with defaults.
- **Exit:** tool, snapping, grid, and marquee acceptance criteria pass by hand and in canvas tests; a drag is one undo step.

### M6. Details panel
- SwiftUI form: title (focused on open), description, kind, links, scrolling.
- Slide-in and zoom-to-fit animation; restore zoom and pan on close; switching regions re-fits.
- Return, Tab, Escape behavior and blank-title rules (D2).
- Keybind suspension while a text field is active.
- **Exit:** all details panel acceptance criteria pass; one field edit session is one undo step.

### M7. Selection and editing
- Select parent and children, Cmd-A, delete with confirmation for regions with children, copy/paste/duplicate (new IDs, links kept, across screens), nudge, bring to front and send to back, `D` and `Shift-D` description display.
- **Exit:** every Section 7 behavior works and undoes.

### M8. Screens, viewports, variants, links
- Sidebar operations and screen kinds; delete-with-incoming-links confirmation that removes those links.
- Viewport presets, This Device (measured on create, with Refresh), Custom, saving user presets.
- Variant groups and "New variant".
- Link indicators, follow with Cmd-click or `L` (menu when there are several), Back/Forward history, next/previous screen.
- **Exit:** screens and links acceptance criteria pass, except scrolling.

### M9. Scrolling
- Scroll settings on screens and regions; drawing the content area and viewport line; marking only past the content area.
- Scroll-in-region on a selected scrollable region instead of canvas pan; clipping of content outside the frame; offsets kept in editor state.
- Parenting uses the content area.
- **Exit:** a child can be placed in hidden content of a scrollable region and saved with absolute coordinates.

### M10. Settings
- `SettingsStore` with file watching, error banner, keybind overrides applied live, user presets persisted.
- **Exit:** settings acceptance criteria pass, including hand edits applying without relaunch and an invalid file leaving settings and the file untouched.

### M11. Exports
- Markdown outline and single-file JSON in the core, with golden tests.
- PNG per screen at 1× and 2×, rendered by the canvas renderer into an offscreen bitmap, honoring description visibility.
- **Exit:** each export matches its fixture for the sample project; PNGs render every screen.

### M12. Hardening and acceptance pass
- Undo audit across every command path.
- Keybind-suppression audit across every text field.
- 500-region performance check on drag, pan, and zoom.
- Walk the full acceptance list (Section 7) and fix gaps.
- **Exit:** every box in spec Section 13 is checked.

### Order and parallelism
M0 → M1 → M2 is the critical path. After M3, the work splits into two tracks that can run at the same time:

- **Canvas track:** M4 → M5 → M6 → M7 → M9
- **Project track:** M8 (sidebar and viewports can start before M5; link following needs M5), M10, and the Markdown and JSON parts of M11

PNG export waits for M4's renderer. M12 closes both tracks.

---

## 6. Testing Strategy

- **Core unit tests** (`swift test`): model, writer, reader, package I/O, every command and its inverse, parenting, snapping, exports. Most acceptance criteria about rules are proved here.
- **Golden fixtures:** a small sample project (Login, Login Desktop, Reset Password, Settings, an account menu overlay, a scrolling list) checked in as a `.uidesc` package, with expected Markdown and single-file JSON exports.
- **App tests:** canvas geometry (view to model coordinates at different zooms), tool state machine, keybind suppression, settings reload.
- **UI tests:** a few XCUITest flows for the details panel (draw, type, Return, Escape, blank discard) and save/reopen.
- **Performance:** an XCTest `measure` block for drawing and hit-testing the 500-region fixture, plus a manual check on hardware each time M4 or M5 changes the renderer.

---

## 7. Acceptance Criteria Map

| Spec 13 criterion | Milestone | Proved by |
|---|---|---|
| `V`/`R`/`W` switch tools with a toast | M5 | Keybind test, manual |
| Region tool draws anywhere; parenting assigns parent | M2, M5 | Parenting unit tests, canvas test |
| Move and resize, snapping, `S`, Option inverts | M2, M5 | Snapping tests, manual |
| `G` grid slider; grid never moves regions | M5 | Unit test (grid change touches no frames) |
| Moving a parent moves children; drag in/out re-parents | M2, M5 | Command tests |
| Marquee, Shift-click, multi move/delete, `Shift-Return` | M5, M7 | Canvas tests |
| Minimum 4 × 4 pt | M2 | Unit test |
| Drawing opens panel, title focused, zoom-to-fit | M6 | UI test |
| Return to description, Escape commits and restores zoom | M6 | UI test |
| Blank-title new region discarded | M6 | UI test, command test |
| Kind, links, scrolling set in panel | M6, M9 | UI test |
| Screen create/rename/reorder/duplicate/delete, kind, viewports | M8 | Command tests, manual |
| Variant groups | M8 | Command tests |
| Follow links, Back/Forward | M8 | App test |
| Scroll a region to place children in hidden content | M9 | Manual, parenting test |
| `.uidesc` package, one file per screen, identical reopen, autosave | M1, M3 | Golden tests, UI test |
| Fixed key order, empty optionals omitted | M1 | Golden tests |
| Different `schemaVersion` refuses to open | M1, M3 | Unit test, manual |
| PNG, Markdown, single-file JSON exports | M11 | Golden tests, manual for PNG |
| Settings and user presets persist across relaunch | M8, M10 | App test |
| Hand edits apply live; invalid file leaves settings untouched | M10 | App test |
| Undo/redo for every change; drag and field session are one step | M2, M5, M6, M12 | Command tests, audit |
| No canvas keybind fires while editing text | M6, M12 | Keybind suppression tests |
| Smooth with 500 regions | M4, M12 | Performance test, manual |

---

## 8. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Canvas can't stay smooth at 500 regions with Core Graphics | Rework of renderer after tools are built on it | Spike at the start of M4 before tools exist; fallback is a layer per region. |
| Scroll-in-region versus canvas pan feels wrong | Hard-to-use placement in hidden content | Isolated in M9 with its own manual check; gesture routing kept in one place in the canvas. |
| Undo grouping drifts as features are added | Acceptance failure on "one drag is one undo step" | All edits go through commands; M12 audit; tests assert undo-stack depth after gestures. |
| Key order or formatting changes silently | Noisy diffs in users' repos | Byte-for-byte golden tests on every CI run. |
| Package writes during autosave are slow or lose files | Data loss | Write only changed screen files; test rename and delete paths; keep `NSDocument` safe-save semantics. |
| Settings watcher misses atomic saves | Hand edits don't apply | Watch the directory, not the file; test with an atomic replace. |

---

## 9. Not in This Plan

Everything in spec Sections 14 and 15: code generation, components, repeated items, migration, collaboration, other platforms, onboarding, accessibility, distribution, reference images, the agent CLI or MCP server, overlay preview, and the fractional layout export. The `references/` folder name stays reserved and is left untouched by the package writer.
