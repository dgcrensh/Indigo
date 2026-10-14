# Document and app shell (milestone 3)

How milestone 3 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on [m1-file-format.md](m1-file-format.md)
and [m2-commands.md](m2-commands.md).

**Status:** shipped

## Goal

Afterwards the app opens, edits and saves real `.uidesc` packages: New, Open, Save, Save As, Revert, autosave and
recent documents all work, a package with another `schemaVersion` is refused with an error, and each document
window has the layout later milestones fill in: a hidden screen sidebar, a canvas placeholder showing the active
screen, a right-hand panel slot, and a menu bar with the standard document commands. Undo and redo go through
`NSUndoManager` to the core's `EditSession`, ready for the first UI that performs commands.

## Scope

**In:**

- The new-project template: a new document has one screen with the default viewport.
- Converting between the core's `PackageTree` and `FileWrapper`, writing only new or changed files and keeping
  files the project doesn't own (such as a `references/` folder or a `.gitignore`).
- `Document` reading through the core (so `schemaVersion` is checked before any screen file is read), writing
  through the core, autosave in place, Revert, Save As, Duplicate, and recent documents.
- The `NSUndoManager` bridge: the document performs a `Command` on its `EditSession` and registers the undo and
  redo steps with the undo manager, using the command's action name.
- The window: an `NSSplitViewController` with a sidebar (hidden by default, toggled with Ctrl-Cmd-S), the canvas
  placeholder, and an inspector slot on the right (collapsed, empty).
- A read-only SwiftUI screen list in the sidebar; selecting a screen makes it the active screen in that window.
- The menu bar skeleton: App, File, Edit, View, Window and Help menus with the items that work in this milestone.

**Out:**

- Drawing the screen, regions, zoom and pan (milestone 4). The canvas placeholder shows the active screen's name,
  kind and viewport as text.
- Adding, renaming, reordering or deleting screens from the sidebar, and saving the last active screen
  (milestone 8). The sidebar only lists screens and picks the active one. The first active screen comes from
  `.editor-state.json` when it names a screen that exists.
- Anything in the inspector slot (milestone 6), and a menu item to show it: the panel opens itself when editing.
- Menu items for features that don't exist yet (tools, zoom, links, screens, exports). Each milestone adds its own.
- Renaming the project from its file name. A new project is named "Untitled" until a later milestone gives the
  name a place in the UI.
- Settings, including the default viewport (milestone 10). The template uses a fixed default.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | New-project template and first active screen | `Packages/DescriberCore/Sources/DescriberCore/Model/Project.swift`, `…/Model/Values.swift` | none |
| 2 | Package changes | `…/Format/ProjectPackage.swift` | none |
| 3 | `FileWrapper` conversion | `InterfaceDescriber/PackageWrapper.swift` | 2 |
| 4 | Document reading, writing and undo bridge | `InterfaceDescriber/Document.swift`, `InterfaceDescriber/DocumentModel.swift` | 1, 3 |
| 5 | Window, sidebar, canvas placeholder, inspector slot | `InterfaceDescriber/DocumentWindowController.swift`, `InterfaceDescriber/ScreenSidebar.swift`, `InterfaceDescriber/CanvasPlaceholder.swift` | 4 |
| 6 | Menu bar skeleton | `InterfaceDescriber/MainMenu.swift` | 5 |

1. **New-project template and first active screen.** `Viewport.defaultForNewScreens` is iPhone 15 (393 × 852 pt,
   preset `iphone-15`) until settings exist. `Project.untitled()` returns a project named "Untitled" with one
   screen, "Screen 1", of kind `screen` at that viewport. `Project.initialScreen` is the editor state's
   `lastActiveScreen` when that screen exists, otherwise the first screen, otherwise nil. Tests: the template
   encodes and reads back, and each case of `initialScreen`.
2. **Package changes.** `ProjectPackage.Changes` holds the files to write (new or different) and the paths to
   delete. `WriteResult.changes` builds it, and `ProjectPackage.applying(_:to:)` applies it to a tree, keeping
   files the project doesn't own. Tests: writing the example over itself changes nothing; renaming a screen writes
   the manifest and the new file and deletes the old one; unknown files survive; applying a write's changes to
   the previous tree gives the write's tree plus the unknown files.
3. **`FileWrapper` conversion.** `PackageWrapper` flattens a directory wrapper into a `PackageTree`, reads one
   file by relative path without touching the others, and applies `Changes` to a directory wrapper in place,
   creating and reusing subdirectory wrappers. Unchanged child wrappers stay as they were, so `NSDocument` can
   copy them instead of rewriting them.
4. **Document reading, writing and undo bridge.** `DocumentModel` (`@Observable`) holds the `EditSession` and
   the active screen. `read(from:ofType:)` reads through `ProjectPackage.read(reading:)` with a lazy reader
   over the wrapper, so an unsupported `schemaVersion` throws the core's `FormatError` (whose message `NSDocument`
   shows) before any screen file is read, and nothing opens. On success the document keeps the wrapper and its
   flattened tree. `fileWrapper(ofType:)` writes the project against that tree and applies the changes to the
   kept wrapper. `autosavesInPlace` is true. `perform(_:)` runs a command on the session and registers an undo
   step named after it; undoing or redoing through `NSUndoManager` calls the session's `undo()` or `redo()` and
   registers the opposite step. Revert replaces the session and clears the undo manager. App tests: the example
   package reads and writes back byte for byte through `FileWrapper`; an unknown file survives a save; a
   `schemaVersion: 2` package throws; a performed command undoes and redoes through the undo manager with its
   action name.
5. **Window, sidebar, canvas placeholder, inspector slot.** `DocumentWindowController` builds an
   `NSSplitViewController` with a sidebar item (collapsed), the canvas placeholder, and an inspector item
   (collapsed). The sidebar hosts a SwiftUI `List` of screen names in project order bound to the active screen.
   The placeholder shows the active screen's name, kind and viewport, or "No screen" when there is none. Both
   follow undo, redo and Revert through Observation. App test: a new document's window has the three items with
   the sidebar and inspector collapsed.
6. **Menu bar skeleton.** File: New, Open, Open Recent (with Clear Menu, filled by `NSDocumentController`),
   Close, Save, Duplicate, Save As (Shift-Option-Cmd-S), Revert to Saved. Edit: Undo, Redo, Cut, Copy, Paste,
   Select All. View: Toggle Sidebar (Ctrl-Cmd-S). Window: Minimize, Zoom, Bring All to Front. Help. App test:
   the File and View items exist with their actions and key equivalents.

## Done when

**Tests and CI:**

- [ ] `Project.untitled()` has one screen at the default viewport and round-trips through the package format.
- [ ] `Project.initialScreen` prefers a valid `lastActiveScreen` and falls back to the first screen.
- [ ] Writing the example project over its own files produces no changes.
- [ ] Renaming a screen produces changes that write the manifest and the new screen file and delete the old one.
- [ ] Files the project doesn't own survive applying a write's changes.
- [ ] (App) The example package reads and writes back byte for byte through `Document` and `FileWrapper`.
- [ ] (App) A package with `schemaVersion: 2` fails to read with the unsupported-version error.
- [ ] (App) A command performed on the document undoes and redoes through its `NSUndoManager`.
- [ ] (App) A new document's window has a collapsed sidebar, the canvas placeholder and a collapsed inspector.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] File > New opens a window titled Untitled; Ctrl-Cmd-S shows a sidebar listing "Screen 1".
- [ ] Saving it as `Test.uidesc` and opening the package in Finder (Show Package Contents) shows `project.json`
  and `screens/screen-1.json`.
- [ ] Opening `Schema/examples/acme.uidesc` lists its five screens in the sidebar; clicking one updates the
  placeholder.
- [ ] Editing `project.json` in a copy of the example to `"schemaVersion": 2` and opening it shows an error and
  no window.
- [ ] File > Open Recent lists the documents just opened.
- [ ] File > Revert to Saved and File > Save As work on an opened document.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Should a new project take its name from the file name on first save? | No; it stays "Untitled" until the name can be edited in the UI. | |
| What is the first screen of a new project called, and at which viewport? | "Screen 1" at iPhone 15 (393 × 852 pt), until settings provide a default viewport. | |
| Should the inspector slot have a menu item to show it before milestone 6? | No; the panel opens itself when a region is edited. | |
