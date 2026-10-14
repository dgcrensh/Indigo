# Settings file and live reload (milestone 10)

How milestone 10 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on
[m3-document-shell.md](m3-document-shell.md), and extends the user presets from
[m8-screens-links.md](m8-screens-links.md) and the keybind registry from [m5-tools-gestures.md](m5-tools-gestures.md).

**Status:** shipped

## Goal

Afterwards `~/Library/Application Support/Interface Describer/settings.json` holds every app setting spec Section 3
lists: the default viewport, the default grid size, whether snapping starts on, user viewport presets, and keybind
overrides. The app watches the file and applies a hand edit to every open window without a relaunch, including an
editor that saves by replacing the file. A file that doesn't read, or has a value the app can't use, shows an error
banner in every window and changes nothing: the settings from before stay in use and the file is never written.
Settings… (Cmd-,) opens the file.

## Scope

**In:**

- `AppSettings` in the core: `defaultViewport`, `gridSize`, `snapping`, `viewportPresets` and `keybindOverrides`,
  each with the default the app used until now (iPhone 15, 8 pt, on, none, none), and the `KeybindRegistry` the
  overrides make.
- Reading the whole file in the core, `SettingsFile.settings(in:)`. Every value is checked, and the first problem is
  an error naming the key and saying what it should be, such as “gridSize” should be one of 4, 8, 12, 16, 24 or 32.
  A missing or blank file is the defaults. Keys:

  ```json
  {
    "defaultViewport": "ipad",
    "gridSize": 16,
    "snapping": false,
    "viewportPresets": [{ "name": "Watch", "width": 198, "height": 242 }],
    "keybinds": { "regionTool": "b", "zoomIn": ["cmd-+", "cmd-="], "followLink": [] }
  }
  ```

  - `defaultViewport`: a built-in preset's ID or name, a user preset's ID or name (ignoring case), `this-device`, or
    `{ "width": n, "height": n }` for a custom size.
  - `gridSize`: one of the `G` popover's steps, so the default is a size the popover can show.
  - `snapping`: `true` or `false`.
  - `keybinds`: an object from action names (`KeyAction` raw values, such as `selectTool`) to a combination in the
    settings form (`v`, `shift-d`, `cmd-option-left`) or a list of them. A list replaces all of the action's
    combinations; an empty list leaves the action without a key. A combination given to two actions is an error.
  - Any other top-level key is an error, so a typo such as `gridsize` is reported instead of ignored.
- Saving a preset (milestone 8) checks the whole file first, so a file with any bad value is never rewritten.
- `SettingsStore` in the app, replacing `UserPresetStore`: the current settings, the error from the last read, and
  a watcher. The watcher follows the folder (an editor's atomic replace) and the file itself (a save in place), waits
  a moment for the writes to settle, and reads the file again when its contents changed. A removed file is the
  defaults again, as at a launch without one. Each applied change posts `SettingsStore.didChangeNotification`.
- Applying a change live:
  - Keybinds: the menu bar's key equivalents, every window's canvas keys, and the key names in toasts.
  - User presets: the Viewport, New Variant and sidebar viewport menus.
  - Grid size: screens that have no grid size of their own draw and snap to the new default straight away.
  - Default viewport: the next new screen and the next new document.
  - Snapping: the next window that opens. An open window keeps the state its `S` key left it in.
- The error banner: a strip across the top of the canvas in every window, with the error and “Your previous
  settings are still in use.”, an Open Settings button, and a close button that hides it until the file changes
  again. It goes away when the file reads.
- Settings… (Cmd-,) in the app menu opens `settings.json` in the app the Mac uses for JSON files, creating the folder
  and a file holding `{}` when there is none. If no app opens it, Finder shows it.
- The settings format documented in `Schema/README.md`.

**Out:**

- A settings window or rebinding UI. The file is edited by hand in v1 (spec 12).
- Removing or renaming user presets in the app (hand edits, as in milestone 8).
- Writing defaults into the file, or formatting it. The app only writes it when a preset is saved, as before.
- Rebinding holding Option to invert snapping, Escape closing the details panel, and the standard Cmd shortcuts the
  menus own outright (New, Open, Save, Close, Cut, Quit). They are not `KeyAction`s.
- Per-document settings. Per-screen grid sizes stay in the editor state, as before.
- Scroll defaults. A region's or screen's new scrolling stays vertical with twice the height (milestone 9).

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | App settings in the core | `…/Format/SettingsFile.swift`, `…/Model/AppSettings.swift`, `…/Model/ViewportPresets.swift`, `…/Model/Project.swift` | none |
| 2 | The settings store and watcher | `InterfaceDescriber/SettingsStore.swift` (replaces `UserPresetStore.swift`) | 1 |
| 3 | Applying settings to windows and menus | `InterfaceDescriber/DocumentModel.swift`, `InterfaceDescriber/DocumentWindowController.swift`, `InterfaceDescriber/CanvasViewController.swift`, `InterfaceDescriber/ScreenController.swift`, `InterfaceDescriber/MainMenu.swift`, `InterfaceDescriber/Keybinds+AppKit.swift`, `InterfaceDescriber/Document.swift`, `InterfaceDescriber/AppDelegate.swift` | 2 |
| 4 | The error banner and Settings… | `InterfaceDescriber/SettingsBanner.swift`, `InterfaceDescriber/AppDelegate.swift`, `Schema/README.md` | 3 |

1. **App settings.** `AppSettings` (Equatable) with `defaultViewport: DefaultViewport` (`.viewport(Viewport)` or
   `.thisDevice`), `gridSize`, `snapping`, `viewportPresets`, `keybindOverrides`, `keybinds` (a registry) and
   `newScreenViewport(displaySize:)` (This Device measured from the display, or iPhone 15 without one).
   `ViewportPresets.preset(named:userPresets:)` finds a preset by ID or name. `SettingsFile.settings(in:)` reads
   every key; `viewportPresets(in:)` stays for the presets alone. `Project.untitled(viewport:)`. Tests: a full file
   reads every value; a missing or blank file is the defaults; each bad value is an error naming its key (wrong
   type, unknown viewport, a grid size off the steps, an unknown action, a combination that doesn't parse, one
   combination on two actions, an unknown key); a default viewport naming a user preset gets its ID; overrides reach
   the registry, an empty list unbinds, and a combination moved to another action leaves its old one.
2. **Store and watcher.** `SettingsStore(url:)` (`@Observable`, main actor) with `settings`, `error`, `reload()`,
   `startWatching()` and `save(name:width:height:)`. Reading keeps the settings from before when the file is bad.
   Saving reads the whole file and throws without writing when it is bad. The watcher uses a dispatch source on the
   folder and one on the file, re-armed after each read, and reads 0.1 s after the last event. App tests with a
   temporary folder: a hand edit applies after `reload()`; an atomic replace and an in-place write are each picked
   up by the watcher on its own; a bad file keeps the settings and sets the error, and the file is unchanged; a
   removed file goes back to the defaults; saving a preset into a file with a bad keybind throws and writes nothing.
3. **Applying settings.** `DocumentModel.settings`, with `keybinds` made from it and `snappingEnabled` starting from
   it. The window controller has a `settingsStore` (the shared one by default; tests give their own), copies its
   settings into the model when the window opens and on each change, and updates the canvas grid. The grid default
   comes from the model's settings. `ScreenController` takes presets and the new screen viewport from the store. The
   menu items with keybinds carry their action, and `MainMenu.applyKeybinds(_:to:)` sets their key equivalents
   again; the app delegate does this on each change. App tests: an override changes the menu item's key equivalent
   and the canvas key, and the toast names the new key; a new grid default redraws a screen without its own grid
   size; a new default viewport is used by New Screen; snapping off applies to a new window only; a bad file leaves
   the keybinds as they were.
4. **Banner and Settings….** `SettingsBanner`, an AppKit view at the top of the canvas showing the store's error
   with Open Settings and close buttons. `AppDelegate.openSettings(_:)` creates the file when missing and opens it.
   `Schema/README.md` gets a settings section with every key. App tests: the banner shows the error in an open
   window, closes until the next change, and hides when the file is fixed; Settings… creates `{}` when there is no
   file and leaves an existing file alone.

## Done when

**Tests and CI:**

- [ ] (Core) A settings file with every key reads into `AppSettings`; a missing or blank file is the defaults.
- [ ] (Core) Each bad value is an error that names its key, and a file with one is never rewritten by saving a
  preset.
- [ ] (Core) Keybind overrides reach the registry: a list replaces the defaults, an empty list unbinds, and a
  combination given to two actions is an error.
- [ ] (App) The watcher applies an edit saved by an atomic replace and one written in place, without `reload()`.
- [ ] (App) A bad file keeps the previous settings, leaves the file unchanged, and shows the banner in an open
  window; fixing the file hides it.
- [ ] (App) A keybind override changes the menu's key equivalent and the canvas key in an open window.
- [ ] (App) The grid default applies to an open window; the default viewport applies to New Screen; the snapping
  default applies to a new window.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Settings… opens `settings.json`. Add `"keybinds": { "regionTool": "b" }` and save: B now picks the Region tool,
  the Tools menu shows B, and R does nothing.
- [ ] Add `"gridSize": 24` and save: the grid in the open window widens at once.
- [ ] Add a stray comma and save: a banner says what is wrong and the B key still works. Fix it: the banner goes.
- [ ] Add a preset to `viewportPresets` by hand: it appears in the Viewport menu without a relaunch.
- [ ] Set `"defaultViewport": "ipad"` and choose New Screen: the new screen is an iPad.
- [ ] Quit and relaunch: every setting is still in use.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Is an unknown key in `settings.json` an error? | Yes, so typos are reported. It makes the whole file invalid, like any other bad value. | |
| Does changing `snapping` flip an open window's snapping? | No. It is the state a new window starts in; `S` decides in an open window. | |
| What does the file name for the grid default? | `gridSize`, one of the popover's steps. | |
| What happens when the file is deleted while the app runs? | The defaults apply, as at a launch without a file. Deleting is not a bad file. | |
| What does Settings… open? | The file itself, in the Mac's app for JSON, created as `{}` when missing. | |
