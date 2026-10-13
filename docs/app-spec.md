# Interface Describer: v1 Spec (Revision 2)

**Working title:** Interface Describer (rename freely)
**Platform:** macOS 14+ desktop app, written in Swift
**Primary user:** The author, describing interfaces for projects built with AI agents
**Primary use case:** Building a file that lives in a project's docs folder and describes the project's interface: its screens, regions, overlays (modals, menus, popovers), and the links between them. Agents read this file when building or changing the UI.

---

## 1. Purpose

Let a user lay out app screens by drawing labeled rectangles on a snapping grid. Each rectangle is a region with a title, an optional kind, and a free-form description of what should exist there. Regions can link to other screens and overlays. The result is a structured, version-controlled description of an interface that agents and other tools can read.

Non-goals for v1:
- No code generation inside the app.
- No pixel-perfect visual design (colors, fonts, icons).
- No collaboration, cloud sync, or Windows/iOS versions.
- No modeling of repeated items. Users describe repetition in text ("list row, repeats for each message").

---

## 2. Core Concepts

| Term | Meaning |
|---|---|
| **Project** | One saved package (`.uidesc`). Contains one or more screens. |
| **Screen** | One canvas with a target viewport. Saved as its own JSON file inside the package. |
| **Screen kind** | What a screen represents: a full `screen`, or an overlay (`modal`, `sheet`, `popover`, `menu`, `alert`). |
| **Variant group** | A set of screens that are the same screen at different viewports (for example, Login on phone and on desktop). |
| **Viewport** | The logical frame, in points, that a screen targets. |
| **Region** | A rectangle on a screen with a title, a kind, and a description. Regions nest and can overlap. |
| **Link** | A reference from a region to another screen ("tapping this opens Settings"). Followable in the editor. |
| **Tool** | The active editing mode (Select, Region, Write), chosen by keybind. |
| **Grid** | Snapping lattice on the canvas. Purely a snapping aid; it never changes stored positions. |

---

## 3. Data Model

### 3.1 Package layout

A project is a macOS document package (a folder that Finder shows as one file). Everything inside is plain, pretty-printed JSON, so agents, editors, and git can read it directly.

```
MyApp.uidesc/
  project.json            Manifest: name, schema version, screen list, variant groups
  screens/
    login.json            One file per screen
    login-desktop.json
    settings.json
    account-menu.json     Overlays are screens too
  .editor-state.json      Editor-only state (safe to gitignore)
```

- **Screen file names** are slugs of the screen name. Renaming a screen renames its file. All references between files use IDs, never file names, so a rename never breaks a link.
- **`.editor-state.json`** holds things that matter to the editor but not to readers of the description: zoom and pan per screen, grid size per screen, description visibility per region, scroll offsets inside scrollable regions, and the last active screen. Keeping it separate keeps the description files free of UI noise and keeps git diffs meaningful.
- **Reserved:** `references/` for reference images (roadmap).

### 3.2 `project.json`

```json
{
  "schemaVersion": 1,
  "name": "Acme",
  "units": "points",
  "screens": [
    { "id": "7f3c...", "name": "Login", "file": "screens/login.json" },
    { "id": "b210...", "name": "Login (Desktop)", "file": "screens/login-desktop.json" },
    { "id": "d44a...", "name": "Reset Password", "file": "screens/reset-password.json" }
  ],
  "variantGroups": [
    { "name": "Login", "screens": ["7f3c...", "b210..."] }
  ]
}
```

The `screens` array order is the order shown in the sidebar. `name` and `file` are written for readers' convenience; the app treats each screen file as the source of truth for its own name.

### 3.3 Screen file

```json
{
  "id": "7f3c...",
  "name": "Login",
  "kind": "screen",
  "viewport": { "preset": "iphone-15", "width": 393, "height": 852 },
  "regions": [
    {
      "id": "a91e...",
      "title": "Sign-in form",
      "kind": "container",
      "x": 16, "y": 200, "w": 361, "h": 240,
      "description": "Vertically stacked form, centered.",
      "children": [
        {
          "id": "c03b...",
          "title": "Email field",
          "kind": "input",
          "x": 32, "y": 224, "w": 329, "h": 44,
          "description": "Single-line input with placeholder 'you@example.com'. Label above it."
        },
        {
          "id": "e7d1...",
          "title": "Forgot password",
          "kind": "button",
          "x": 32, "y": 392, "w": 140, "h": 24,
          "description": "Text-style link button.",
          "linksTo": [
            { "screen": "d44a...", "screenName": "Reset Password", "trigger": "click" }
          ]
        }
      ]
    }
  ]
}
```

### 3.4 Decisions

- **Units are points everywhere.** Region positions and sizes are stored in points, the same unit as the viewport. The grid only affects snapping, so changing grid size never moves or resizes anything. Values are rounded to whole points.
- **Coordinates are absolute** (relative to the screen origin), even for nested regions. A reader never has to add up parent offsets.
- **Nesting is a tree.** Each region has a `children` array. Sibling order in the array is z-order: later siblings draw on top.
- **Fixed key order.** A custom encoder writes keys in this order: `id, title, kind, x, y, w, h, description, scroll, linksTo, children` for regions, and `id, name, kind, viewport, scroll, regions` for screens. Output is pretty-printed with stable formatting so diffs stay small.
- **Empty optional fields are omitted.** No `"children": []`, `"linksTo": []`, `"scroll": null`, or `"kind": "open"` in the file. A region with no `kind` is open.
- **Derived convenience fields.** `screenName` in links and `name`/`file` in the manifest are rewritten on every save and ignored on read. They exist so a reader doesn't have to look up IDs.
- **Region kinds** (optional, chosen in the details panel): `open` (default), `container`, `text`, `image`, `button`, `input`, `toggle`, `picker`, `list`, `navigation`, `menu-item`. The set is small on purpose; the description carries the detail.
- **Scrolling.** A screen or region can carry `"scroll": { "axis": "vertical" | "horizontal" | "both", "contentWidth": n, "contentHeight": n }`. The content area starts at the frame's origin. Children inside scrolling content keep absolute coordinates as if the scroll offset were zero, so a child may extend past its parent's frame but must fit within the content area.
- **Links.** `linksTo` is an array, since a region can do more than one thing (click versus right-click, for example). Each link has a target `screen` ID and an optional free-text `trigger`. How the target appears (pushed, modal, menu) comes from the target screen's `kind`.
- **Schema version.** `schemaVersion` is checked on open. A file with a different version shows an error and is not opened. No migration in v1; the format will change freely until files need to last.

App-wide settings live in `~/Library/Application Support/<AppName>/settings.json`: default viewport, default grid size, snap default, user viewport presets, and keybind overrides. See Section 12 for reload and error behavior.

---

## 4. Canvas

- The canvas fills the window. A collapsible screen sidebar sits on the left (hidden by default) and the details panel opens on the right when editing (Section 6).
- The screen's viewport is drawn as a bordered frame. Regions can extend past the frame, and those parts are visually marked. For a scrollable screen, the full content area is drawn, with a line marking where the viewport ends; only parts past the content area are marked.
- Grid lines are drawn lightly while snapping is active or while the grid size is being adjusted.
- Pan with two-finger scroll. Zoom with pinch or Cmd +/−. Cmd 0 resets zoom.
- Titles always show on regions, truncated to fit. Descriptions can also be shown on the canvas, read-only, toggled with `D` / `Shift-D`.
- **Toasts.** A small, non-interactive label near the bottom center of the canvas confirms mode changes: tool changes ("Region tool — R"), snapping on/off, and grid size. It fades after about a second and never takes focus.

---

## 5. Tools

The active tool decides what clicks and drags do. Tools are chosen by keybind, and a toast confirms the change. The tool stays active until another is chosen.

| Tool | Key | Drag | Click (no drag) | Double-click |
|---|---|---|---|---|
| **Select** | `V` | On a region: move it (or the whole selection). On a handle: resize. On empty canvas: marquee selection of regions it touches. | On a region: select it. Shift-click adds or removes. On empty canvas: clear selection. Cmd-click a linked region: follow its link. | Open the region in the details panel. |
| **Region** | `R` | Draw a new region anywhere, including inside existing regions. On release, the details panel opens for it (Section 6). | Nothing. | Nothing. |
| **Write** | `W` | Nothing. | On a region: open it in the details panel. On empty canvas: close the panel. | Same as click. |

Rules that apply to every tool:
- **Minimum region size** is 4 × 4 pt. A drag smaller than that is treated as a click.
- **Snapping** applies to drawing, moving, and resizing while active. Holding Option inverts it for the current gesture.
- **Parenting rule.** After any create, move, or resize, a region's parent is the smallest region on the screen whose content area fully contains it. If two candidates are the same size, the one on top wins. If nothing contains it, it is a top-level region. This one rule covers drawing a child, dragging a region into or out of another, and children left outside a resized parent.
- Moving or resizing a parent moves its children with it.
- **Scrolling inside a region.** When the pointer is over a selected scrollable region, two-finger scroll scrolls that region's content instead of panning the canvas. This is how users place children in content that is outside the visible frame. Content outside the frame is clipped while not scrolled into view.

---

## 6. Details Panel

The details panel is where titles, descriptions, kinds, links, and scrolling are edited. Regions are never edited inline on the canvas.

### 6.1 Opening
The panel opens when:
- A region is drawn with the Region tool (on mouse release).
- A region is clicked with the Write tool.
- A region is double-clicked with the Select tool.

When it opens, the panel slides in from the right and the canvas animates to zoom-to-fit the region in the remaining area on the left, with some padding. When the panel closes, the canvas animates back to the zoom and pan it had before.

### 6.2 Fields
In order, top to bottom:
1. **Title.** Single line. Has focus as soon as the panel opens.
2. **Description.** Multi-line, visually separate from the title.
3. **Kind.** Pop-up menu, default Open.
4. **Links.** List of links, each with a target screen (pop-up of the project's screens) and an optional trigger text. Add and remove buttons.
5. **Scrolling.** Off by default. When on: axis, content width, and content height.

### 6.3 Keys while editing
- **Return in the title** moves focus to the description.
- **Return in the description** inserts a new line.
- **Tab / Shift-Tab** move between fields.
- **Escape** commits and closes the panel. Escape does not discard text; undo covers mistakes.
- **Blank fields:** If a newly drawn region has a blank title when the panel closes, the region is discarded. For an existing region, a title cleared to blank reverts to its previous value. A blank description is allowed.
- While any text field is being edited, all canvas and tool keybinds are disabled. Only text-editing keys, Escape, Tab, and standard Cmd shortcuts (copy, paste, undo) work.

### 6.4 Switching regions
With the panel open, clicking another region with the Write tool (or double-clicking with Select) commits the current region and opens the new one. The canvas re-fits to the new region.

---

## 7. Selection and Editing

- Shift-click toggles a region in the selection. Marquee (Select tool, drag on empty canvas) selects every region it touches. Cmd-A selects all regions on the screen.
- **Select parent** (`Shift-Return`) replaces the selection with the parent of the selected region. This reaches parents that are fully covered by their children. **Select children** (`Return`) selects the selected region's direct children.
- Multi-selection supports move and delete. Resize works on a single region.
- Delete or Backspace removes the selection. Deleting a region with children asks for confirmation and deletes the children too.
- Copy, paste, and duplicate (Cmd-C, Cmd-V, Cmd-D) work on regions, including pasting onto another screen. Pasted and duplicated regions get new IDs, and links on them are kept.
- Arrow keys nudge the selection by one grid step (or 1 pt with snapping off). Shift-arrow nudges by four steps.
- Bring to front and send to back reorder the region among its siblings.

---

## 8. Screens, Overlays, Variants, and Links

### 8.1 Screens
- The sidebar lists screens in project order. The user can add, rename, duplicate, reorder, and delete screens.
- Each screen has a kind: `screen`, `modal`, `sheet`, `popover`, `menu`, or `alert`. Overlays are ordinary screens with their own viewport sized to the overlay itself (for example, a 240 × 180 menu). Menu items are regions, typically of kind `menu-item`.
- Deleting a screen that other regions link to asks for confirmation and removes those links.

### 8.2 Viewports
- **Built-in presets:** iPhone (several sizes), iPad, a common laptop size, a common desktop size, This Device, and Custom.
- **This Device** uses the full logical resolution of the display the window is on (the whole screen, including menu bar and Dock areas), measured when the screen is created. A "Refresh to current display" action updates it.
- **Custom** accepts any width and height in points.
- **User presets:** any viewport can be saved as a named preset. User presets are stored in settings and appear alongside the built-ins.
- Changing a viewport does not move regions. It only changes the frame drawn on the canvas and the saved value.

### 8.3 Variants
- Screens can be grouped as variants of one another (the same screen at different viewports). Variants appear together in the sidebar.
- A "New variant" action duplicates a screen into the same group with a new viewport. After that, variants are edited independently.

### 8.4 Following links
- Cmd-click a linked region (Select tool), or press `L` with one linked region selected, to open the target screen. If the region has more than one link, a menu lists them.
- **Back / Forward** (Cmd-Option-← / Cmd-Option-→) move through link-following history, like a browser.
- Regions with links show a small link indicator on the canvas.

---

## 9. Keybinds (defaults, all rebindable through settings)

All keybinds are disabled while a text field is being edited (Section 6.3).

| Action | Default | Notes |
|---|---|---|
| Select tool | `V` | Toast on change. |
| Region tool | `R` | Toast on change. |
| Write tool | `W` | Toast on change. |
| Toggle snapping | `S` | On by default. Toast on change. |
| Invert snapping (temporary) | Hold Option | For the current gesture only. |
| Adjust grid size | `G` | Popover slider with fixed steps: 4, 8, 12, 16, 24, 32 pt. |
| Toggle description visibility (selection) | `D` | Canvas display only. |
| Toggle description visibility (all) | `Shift-D` | Canvas display only. |
| Select parent | `Shift-Return` | |
| Select children | `Return` | |
| Select all | Cmd-A | |
| Copy / paste / duplicate | Cmd-C / Cmd-V / Cmd-D | |
| Nudge | Arrow keys, Shift-arrow | |
| Delete selection | Delete / Backspace | |
| Undo / Redo | Cmd-Z / Shift-Cmd-Z | |
| Bring to front / send to back | Cmd-] / Cmd-[ | Within siblings. |
| Follow link | `L`, or Cmd-click | |
| Back / Forward (links) | Cmd-Option-← / Cmd-Option-→ | |
| Next / previous screen | Cmd-Option-↓ / Cmd-Option-↑ | Replaces Ctrl-Tab, which macOS uses for window tabs. |
| Toggle sidebar | Ctrl-Cmd-S | macOS standard. |
| Zoom in / out / reset | Cmd +, Cmd −, Cmd 0 | |

Every action also appears in the menu bar.

---

## 10. Persistence

- Native document model with Open, Save, Save As, Revert, and autosave. The document reads and writes the package as a whole.
- File extension `.uidesc` (placeholder), declared as a document package type.
- Recent documents appear in the File menu.
- The package is designed to be committed to a project's repository. `.editor-state.json` can be gitignored.

---

## 11. Exports

Exports write files alongside the package (or wherever the user chooses). The package itself remains the canonical format.

- **PNG per screen.** Renders each screen at 1× or 2×, showing regions, titles, link indicators, and descriptions according to the current visibility settings. Useful for multimodal agents and for humans reviewing the design.
- **Markdown outline.** One `.md` file for the whole project: each screen as a section with its kind, viewport, and variants, then a nested outline of regions with kind, position, size, description, and links written as in-document anchors to the target screen's section.
- **Single-file JSON.** The whole project flattened into one `.json` file (manifest plus all screens inline), for tools or chat apps that can't read a package folder.

---

## 12. Architecture (under discussion)

No framework choices are settled yet. The current recommendation, to be confirmed:

- **Canvas: AppKit** (`NSView` drawing with Core Graphics or Core Animation). The canvas needs precise hit testing, modifier-key handling, cursor changes, and the scroll-in-region versus pan distinction. Moving all text editing into the panel removes the hardest AppKit work (inline text over a zoomed canvas).
- **Details panel, sidebar, toasts, popovers, settings: SwiftUI**, hosted in AppKit. The panel is a form, which is what SwiftUI does best.
- **Document handling: `NSDocument`** reading and writing the package with `FileWrapper`. Alternative: SwiftUI `DocumentGroup` with `ReferenceFileDocument`, which gives less control over package writes and autosave.
- **Model:** `Project` → `[Screen]` → region tree, using Observation (`@Observable`). All edits go through a command layer, so every change is undoable through `NSUndoManager` and testable without the UI.
- **Keybinds:** a `KeybindRegistry` mapping actions to key combinations, reading overrides from settings, and suppressed while text is being edited.
- **Settings storage (decided): `settings.json`.** Keybind overrides and user presets are structured data that will be hand-edited until a rebinding UI exists, and JSON keeps one persistence format across the app.
  - **Reload on change.** The app watches the file and applies edits immediately, without a relaunch.
  - **Bad file handling.** If the file fails to parse, the app keeps its current settings and shows the error. It never resets to defaults or overwrites the file.

Minimum macOS version: **14 (Sonoma)**, for Observation.

---

## 13. Acceptance Criteria (v1)

Tools and canvas:
- [ ] `V`, `R`, and `W` switch tools, and a toast names the active tool.
- [ ] With the Region tool, dragging anywhere (including inside a region) creates a region, and the parenting rule assigns its parent.
- [ ] Regions can be moved and resized, and snap while snapping is on. `S` toggles snapping and holding Option inverts it.
- [ ] `G` opens a grid-size slider with fixed steps. Changing it never moves or resizes regions.
- [ ] Moving a parent moves its children. Dragging a region into or out of another re-parents it.
- [ ] Marquee and Shift-click build a multi-selection. Move and delete work on it. `Shift-Return` selects the parent.
- [ ] Regions smaller than 4 × 4 pt cannot be created.

Details panel:
- [ ] Drawing a region opens the panel with the title focused and the canvas zoomed to fit the region on the left.
- [ ] Return moves from title to description. Escape commits and closes, restoring the previous zoom and pan.
- [ ] A new region with a blank title is discarded on close.
- [ ] Kind, links, and scrolling can be set in the panel.

Screens and links:
- [ ] Screens can be created, renamed, reordered, duplicated, deleted, and given a kind and viewport, including This Device, Custom, and user presets.
- [ ] Screens can be grouped as variants.
- [ ] Links can be followed with Cmd-click or `L`, and Back/Forward return through the history.
- [ ] A scrollable region can be scrolled in the editor to place children in its hidden content.

Persistence and export:
- [ ] A project saves as a `.uidesc` package with one JSON file per screen, reopens with identical content, and autosaves.
- [ ] Saved JSON uses the fixed key order and omits empty optional fields.
- [ ] Opening a package with a different `schemaVersion` shows an error and opens nothing.
- [ ] PNG, Markdown, and single-file JSON exports produce files matching the project's content.
- [ ] App settings, including user presets, persist across relaunch.
- [ ] Hand edits to `settings.json` apply without relaunching. An invalid file shows an error and leaves the current settings and the file untouched.

Quality:
- [ ] Undo and redo work for every canvas, panel, and screen change. A single drag is one undo step, and one panel editing session on a field is one undo step.
- [ ] No canvas or tool keybind fires while a text field is being edited.
- [ ] Pan, zoom, and drag stay smooth with 500 regions on a screen.

---

## 14. Out of Scope for v1

- Generating prompts or code
- Reusable components or templates
- Modeling repeated items
- File format migration
- Multi-user editing
- Windows, iOS, or web versions
- Onboarding and discoverability aids
- Accessibility support
- Distribution (signing, notarization, App Store, updates)

---

## 15. Roadmap

- **Reference images.** Place a screenshot or sketch under a screen to trace over. Stored in `references/` inside the package.
- **Agent extraction tool.** A CLI or MCP server that lets agents query the package efficiently (for example, "list screens," "get region tree for Settings," "what links to Login") instead of reading whole files.
- **Overlay preview.** Show an overlay screen on top of the screen that links to it.
- **Fractional layout view.** A derived export with each region's position as fractions of the viewport, to help with responsive layouts.

---

## 16. Open Questions

1. **Blank fields.** This spec reads "a blank title/description gets aborted" as: a new region with a blank title is discarded, a cleared title on an existing region reverts, and a blank description is allowed. Is that right, or should a blank description also discard a new region?
2. **Architecture.** See Section 12.
3. **PNG renders in the package.** Should the package automatically include an up-to-date PNG of each screen on save, so agents always have an image next to the JSON? This costs repository size and diff noise.
4. **Link presentation.** The target screen's kind decides how it's presented. Is there a case where the same screen is shown two ways (pushed in one place, modal in another) that needs a per-link override?
5. **Working title and file extension.** Both are placeholders.
