# Screens, viewports, variants and links (milestone 8)

How milestone 8 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on
[m3-document-shell.md](m3-document-shell.md) and, for following links from the canvas,
[m5-tools-gestures.md](m5-tools-gestures.md).

**Status:** shipped

## Goal

Afterwards the project's screens are managed in the app, as spec Section 8 describes: the sidebar adds, renames,
duplicates, reorders and deletes screens and shows variant groups together; each screen gets a kind and a viewport
from the built-in presets, This Device, a custom size or a preset the user saved; "New Variant" copies a screen into
its variant group at another viewport. Links are followed with Cmd-click or `L`, Back and Forward walk the
link-following history, Cmd-Option-↓ and ↑ step through the screens, and linked regions show a link indicator.

## Scope

**In:**

- Sidebar order in the core: the order the sidebar shows (project order, with each variant group's screens pulled
  together at its first screen), the rows it draws (a header row for each group above its screens), and the new
  screen order after a drag. Commands that add, duplicate or group screens keep each group's screens next to each
  other in the project, so the file order and the sidebar order stay the same.
- New screen commands: `ReorderScreens` (a whole new order, from a sidebar drag, one "Move Screen" step),
  `JoinVariants` (puts a screen in another screen's group, creating the group when that screen has none),
  `LeaveVariantGroup` (takes one screen out; a group left with one screen is dissolved), and renaming a variant
  group. `DeleteScreen` refuses to delete the only screen, since a project has one or more (spec Section 2).
- Screen naming in the core: the next free "Screen N" name for a new screen, and a typed name trimmed, with a blank
  name refused so the old name stays.
- The delete-screen question in the core: "Delete “Reset Password”? 2 regions on other screens link to it, and
  those links will be removed." Asked only when other screens link to it (spec 8.1).
- Viewport presets in the core (spec 8.2): the built-in list (iPhone SE, iPhone 15, iPhone 15 Pro Max, iPad, iPad
  Pro 13-inch, Laptop, Desktop), This Device (preset `this-device`, measured by the app), Custom (no preset), and
  user presets. A label for any viewport, such as "iPhone 15 — 393 × 852" or "Custom — 500 × 400".
- User presets in `settings.json` (spec 3, decided in spec 12): a `viewportPresets` array of `{name, width,
  height}`. The core reads them and writes the file back with only that key replaced, keeping every other key and
  its order. A file that doesn't parse is never written; the app shows the error instead. A small JSON reader that
  keeps key order is added for this, so milestone 10 can reuse it.
- Link following in the core: the links of a region that point at screens in the project, with menu titles such as
  "Reset Password — click"; a browser-style history (following pushes the current screen on Back and clears
  Forward; screens deleted since are skipped); the next and previous screen in sidebar order, stopping at the ends.
- `CanvasGesture`: a Select-tool Cmd-click on a region with links asks to follow them instead of moving or
  selecting; on a region without links it is an ordinary click.
- The app's sidebar (SwiftUI): screens with a kind icon, group header rows, drag to reorder, inline rename, and a
  context menu (Rename, Duplicate, New Variant, Make Variant Of, Remove from Variant Group, Rename Group, Delete).
  Under the list, the active screen's kind and viewport: a kind pop-up, a viewport pop-up (presets, This Device,
  Custom) and width and height fields. Selecting a screen makes it active.
- A Screen menu: New Screen, Duplicate Screen, Rename Screen…, Delete Screen…, Kind (submenu), Viewport (submenu
  with the presets, This Device, Custom Size…, Refresh to Current Display, Save Viewport as Preset…), New Variant
  (submenu of viewports), Make Variant Of (submenu of screens), Remove from Variant Group. A Go menu: Back,
  Forward, Follow Link, Next Screen, Previous Screen, with the spec Section 9 keys from the registry.
- This Device measures the logical size of the whole display the window is on, when chosen; Refresh to Current
  Display measures again (enabled only for a This Device viewport).
- `L` with one selected region that has links follows it; with several links a menu lists them, at the region for
  `L` and at the pointer for Cmd-click.
- A small link indicator in the top-right corner of every region with links, drawn as a layer like the title.
- The active screen is saved as `lastActiveScreen` in `.editor-state.json` when the user changes it (spec 3.1).
  After an undo removes the active screen, the screen that took its place in the sidebar becomes active.
- New, duplicated and new-variant screens become the active screen.

**Out:**

- Watching `settings.json`, the error banner, keybind overrides and the default viewport, grid and snap settings
  (milestone 10). This milestone reads the presets when the app starts and again before saving one.
- Removing or renaming user presets in the app. They are edited in `settings.json` by hand until milestone 10's
  reload exists.
- A per-link presentation override (roadmap D4).
- Overlay preview (spec Section 15).
- Recording sidebar and next/previous screen moves in the Back/Forward history. Only link following is history.
- Editing the screen's scroll settings in the sidebar (milestone 9).
- Undo for the active screen, the history and the sidebar's selection. They are editor state, not edits.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Sidebar order and the new screen commands | `…/Editing/SidebarOutline.swift`, `…/Commands/ScreenCommands.swift` | none |
| 2 | Screen names, the delete question, navigation and link targets | `…/Editing/ScreenEditing.swift` | 1 |
| 3 | Viewport presets and the settings file | `…/Model/ViewportPresets.swift`, `…/Format/JSONReader.swift`, `…/Format/SettingsFile.swift` | none |
| 4 | Cmd-click in the gesture | `…/Editing/CanvasGesture.swift` | none |
| 5 | Model, screen controller and preset store | `InterfaceDescriber/DocumentModel.swift`, `InterfaceDescriber/ScreenController.swift`, `InterfaceDescriber/UserPresetStore.swift`, `InterfaceDescriber/Document.swift` | 1, 2, 3 |
| 6 | Sidebar | `InterfaceDescriber/ScreenSidebar.swift` | 5 |
| 7 | Following links and the link indicator | `InterfaceDescriber/CanvasViewController.swift`, `InterfaceDescriber/RegionLayers.swift`, `InterfaceDescriber/CanvasView.swift` | 4, 5 |
| 8 | Screen and Go menus | `InterfaceDescriber/MainMenu.swift`, `InterfaceDescriber/DocumentWindowController.swift` | 5, 7 |

1. **Sidebar order.** `SidebarOutline(project:)` gives `screens` (sidebar order) and `rows` (`.group(index)` headers
   and `.screen(id, group:)` rows). `SidebarOutline.order(afterMoving:to:)` maps a drag of screen rows to a new
   screen order, then pulls groups together again, so a screen dropped inside a group it isn't in lands after the
   group and a member dragged away takes its group along. `Project.groupingVariants()` reorders `screens` to the
   sidebar order; `AddScreen`, `DuplicateScreen` and `GroupVariants` call it. `ReorderScreens`, `JoinVariants`,
   `LeaveVariantGroup` and `RenameVariantGroup` undo through `RestoreStructure`. Tests: rows for the example; a
   non-contiguous group is pulled together; dragging into and out of a group; every new command undoes to the same
   bytes; deleting the only screen throws.
2. **Screen editing helpers.** `ScreenNames.newScreenName(in:)`, `ScreenNames.cleaned(_:)`,
   `ScreenDeleteConfirmation.message(deleting:in:)`, `ScreenNavigation.neighbor(of:offset:in:)`,
   `ScreenNavigation.replacement(forRemoved:previousOrder:in:)` (the screen that takes a removed one's place),
   `LinkTargets.entries(for:in:)`, and `NavigationHistory` with `visit`, `back`, `forward`, `canGoBack` and
   `canGoForward`, skipping screens no longer in the project. Tests for each.
3. **Presets and settings.** `ViewportPreset` (`id`, `name`, `width`, `height`), `ViewportPresets.builtIn`,
   `ViewportPresets.thisDevice(width:height:)`, `ViewportPresets.label(for:userPresets:)` and the user preset IDs
   (the slug of the name, made unique against the built-ins and each other). `JSONReader.parse(_:)` reads JSON into
   a `JSONValue` keeping key order, with a message and line for bad input. `SettingsFile.viewportPresets(in:)` and
   `SettingsFile.replacingViewportPresets(_:in:)`. Tests: parse and write back keeps other keys in order; a missing
   file starts from `{}`; a bad file throws and nothing is returned; bad preset entries are an error naming them.
4. **Cmd-click.** A Select-tool press with Command on a region that has links sets `linkRequest` on release when
   it wasn't dragged, selects that region, and never moves it. Tests: Cmd-click a linked region; Cmd-click an
   unlinked region selects it; Cmd-drag a linked region moves nothing.
5. **App model and controller.** `DocumentModel` keeps the history and writes `lastActiveScreen` when the active
   screen changes (not when a document is read), and after any change replaces a missing active screen.
   `ScreenController` performs each screen action as one command (new, duplicate, rename, delete with the question,
   kind, viewport, This Device, refresh, custom size, save preset, new variant, make variant of, remove from group,
   rename group, move), navigates (follow, back, forward, next, previous), and asks through replaceable closures so
   tests answer for the user. `UserPresetStore` reads and writes `~/Library/Application Support/Interface
   Describer/settings.json`; tests give it a temporary file. App tests for each action's step and name, the delete
   question, This Device using the measured size, presets saved to the file and offered afterwards, a bad file left
   untouched, and the active screen after undo.
6. **Sidebar.** Rows from `SidebarOutline`, the group headers not draggable, `onMove` calling the controller, a
   rename text field, the context menu, and the kind and viewport controls for the active screen at the bottom.
7. **Links on the canvas.** `L` and Cmd-click call the controller; several links show a menu. `RegionLayers` gains
   a link indicator layer, shown when the region has links and is big enough, with the title shortened to leave
   room. App tests: Cmd-click and `L` follow, the menu chooser picks among several, Back and Forward return, the
   indicator shows only on linked regions.
8. **Menus.** The Screen and Go menus above; the window controller validates them (Delete off with one screen,
   Back and Forward off without history, Follow Link off without one linked region selected, Refresh only for This
   Device, everything with a Cmd key off while text is being edited, `L` only while the canvas has focus) and shows
   checkmarks for the screen's kind and viewport preset. App tests: items and keys, and validation.

## Done when

**Tests and CI:**

- [ ] (Core) The sidebar order pulls each variant group together, and a drag gives the expected order into, out of
  and within a group.
- [ ] (Core) `ReorderScreens`, `JoinVariants`, `LeaveVariantGroup` and `RenameVariantGroup` undo and redo to the
  same bytes, and the only screen can't be deleted.
- [ ] (Core) New screen names, blank renames, the delete question, next and previous screen, and link targets give
  the spec results.
- [ ] (Core) The history goes back and forward like a browser and skips deleted screens.
- [ ] (Core) Viewport labels name the built-in, This Device, custom and user presets.
- [ ] (Core) Saving presets into a settings file keeps its other keys in order; a bad file is never rewritten.
- [ ] (Core) A Select-tool Cmd-click on a linked region asks to follow it and moves nothing.
- [ ] (App) New, duplicate, rename, reorder, delete, kind, viewport and variant actions are one named undo step
  each, and deleting a linked screen asks first and removes the links.
- [ ] (App) This Device uses the measured display size; a saved preset reaches `settings.json` and the viewport
  menu.
- [ ] (App) Cmd-click and `L` follow a link, a chooser picks among several, and Back and Forward return.
- [ ] (App) Linked regions show the link indicator and others don't.
- [ ] (App) The Screen and Go menu items have their spec keys and are disabled when they can't act.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Show the sidebar (Ctrl-Cmd-S). Login and Login (Desktop) sit under a "Login" group header.
- [ ] Screen > New Screen adds "Screen 1" after the active screen and shows it; rename it in the sidebar; drag it
  above Login; Cmd-Z undoes each step.
- [ ] Delete Reset Password: it asks, because Login links to it; after deleting, Login's "Forgot password" has no
  link; Cmd-Z brings both back.
- [ ] Set a screen to This Device: the frame matches the display. Set a custom 500 × 400 size, save it as a preset,
  quit and relaunch: the preset is in the Viewport menu.
- [ ] New Variant on Settings at iPad: "Settings (iPad)" appears under a new "Settings" group.
- [ ] Cmd-click "Forgot password" on Login: Reset Password shows. Cmd-Option-← goes back to Login, Cmd-Option-→
  forward again. `L` with the region selected does the same.
- [ ] Cmd-Option-↓ and ↑ step through the screens in sidebar order.
- [ ] Linked regions show the link indicator.
- [ ] Close and reopen the document: it opens on the screen that was showing.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| How does the sidebar show variant groups? | A header row with the group's name above its screens, which sit next to each other. | |
| Do Next and Previous Screen wrap around? | No; they stop at the ends. | |
| Do sidebar and next/previous moves join the Back/Forward history? | No, only following links does. | |
| Can the last screen be deleted? | No. | |
| Which viewport does a new screen get? | `iphone-15`, 393 × 852, until settings have a default viewport (milestone 10). | |
| What `preset` value does a user preset write? | The slug of its name, such as `my-watch`. | |
