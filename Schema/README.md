# The `.uidesc` package format

A `.uidesc` project is a folder (macOS shows it as one document) of pretty-printed JSON. This page is the short
version, for agents and people reading or writing packages by hand. The full rules are in
[spec Section 3](../docs/app-spec.md#3-data-model), and [uidesc-1.schema.json](uidesc-1.schema.json) is a JSON
Schema (2020-12) that both `project.json` and each screen file validate against.

```
Acme.uidesc/
  project.json            Manifest: schema version, project name, screen list, variant groups
  screens/
    login.json            One file per screen, named by a slug of the screen's name
    account-menu.json     Overlays (modal, sheet, popover, menu, alert) are screens too
  .editor-state.json      Zoom, pan, grid and scroll positions; editor-only, safe to gitignore
```

## Rules a writer must follow

- **`schemaVersion` is `1`.** The app refuses to open any other version.
- **Files refer to each other by ID**, never by file name. IDs are lowercase UUIDs. Region IDs are unique across
  the whole project, not just their screen.
- **Screen file names are slugs** of the screen name: lowercase, runs of other characters become `-`, and a repeat
  gets `-2`, `-3` in sidebar order. Renaming a screen renames its file.
- **The manifest's `screens` order is the sidebar order.** Each entry's `file` is where the app looks for the
  screen; its `name` is only a convenience copy.
- **Coordinates are absolute points** from the screen's top-left corner, even for nested regions, and are whole
  numbers. Regions are at least 4 × 4 points.
- **Nesting is a tree.** A region's `children` are the regions inside it, and later siblings draw on top.
- **Keys come in a fixed order** and **empty optional fields are left out**:
  - region: `id, title, kind, x, y, w, h, description, scroll, linksTo, children`, with no `kind` for an open
    region, and no empty `children` or `linksTo`, and no `scroll` unless it scrolls;
  - screen: `id, name, kind, viewport, scroll, regions`;
  - manifest: `schemaVersion, name, units, screens, variantGroups`, with no `variantGroups` when there are none.
- **Derived fields** (`screenName` on a link, `name` and `file` in the manifest) are rewritten by the app on
  every save and ignored when it reads.
- **Formatting** is 2-space indentation, one key per line, and a trailing newline. The app writes exactly this, so
  a package it saves round-trips byte for byte and git diffs stay small.

## Kinds

- Screen `kind`: `screen`, `modal`, `sheet`, `popover`, `menu`, `alert`.
- Region `kind`: `container`, `text`, `image`, `button`, `input`, `toggle`, `picker`, `list`, `navigation`,
  `menu-item`, or absent for an open region.
- `viewport.preset`: a built-in preset (`iphone-se`, `iphone-15`, `iphone-15-pro-max`, `ipad`, `ipad-pro-13`,
  `laptop`, `desktop`), `this-device` for a size measured from the author's display, or the slug of a preset the
  author saved in the app's settings. Absent for a custom size. `width` and `height` are always the real size.
- `scroll.axis`: `vertical`, `horizontal`, `both`. The content area starts at the frame's origin and is
  `contentWidth` × `contentHeight`; children of a scrolling region must fit in it rather than in the frame.

## The example

[examples/acme.uidesc](examples/acme.uidesc) has a Login screen and its desktop variant, Reset Password, a Settings
screen with a vertically scrolling list, and an account menu overlay, with nested regions and links between them.
It is generated from `Packages/DescriberCore/Tests/DescriberCoreTests/Support/AcmeExample.swift`; after changing
that file or the format, regenerate it with

```sh
REGENERATE_EXAMPLE=1 swift test --package-path Packages/DescriberCore --filter testRegenerateExample
```

`scripts/check.sh` fails if the example doesn't re-save byte for byte or doesn't match the schema.

## App settings

The app's own settings live outside any package, in `~/Library/Application Support/Interface Describer/settings.json`
(Settings… in the app menu opens it). The app watches the file and applies a saved edit at once. If the file
doesn't parse or has a value the app can't use, every window shows the error and the settings from before stay in
use; the app never rewrites such a file. Every key is optional, and any other key is an error:

```json
{
  "defaultViewport": "ipad",
  "gridSize": 16,
  "snapping": false,
  "viewportPresets": [
    { "name": "Watch", "width": 198, "height": 242 }
  ],
  "keybinds": { "regionTool": "b", "zoomIn": ["cmd-+", "cmd-="], "followLink": [] }
}
```

- `defaultViewport`: the viewport of a new screen or document. A preset's ID or name (built-in or one of
  `viewportPresets`, case doesn't matter), `this-device`, or `{ "width": n, "height": n }`. Default `iphone-15`.
- `gridSize`: the grid of a screen that hasn't had its own chosen with `G`: 4, 8, 12, 16, 24 or 32. Default 8.
- `snapping`: whether snapping is on when a window opens. Default `true`.
- `viewportPresets`: the user's presets, each with a `name` and a whole-number `width` and `height`. Save Viewport as
  Preset… adds to this list and keeps the rest of the file as it is.
- `keybinds`: action names mapped to a key, or a list of keys. A list replaces all of the action's default keys, and
  an empty list leaves it without one. A key the file gives to one action is taken from the action that had it by
  default; giving one key to two actions is an error. Keys are modifiers then the key, joined by `-`: `cmd`,
  `shift`, `option` (or `alt`), `ctrl`, then a character or one of `return`, `delete`, `forward-delete`, `escape`,
  `tab`, `space`, `left`, `right`, `up`, `down`. For example `v`, `shift-d`, `cmd-]`, `cmd--`, `cmd-option-left`.

| Action | Default | Action | Default |
| --- | --- | --- | --- |
| `selectTool` | `v` | `nudgeLeft`, `nudgeRight`, `nudgeUp`, `nudgeDown` | `left`, `right`, `up`, `down` |
| `regionTool` | `r` | `nudgeLeftFar`, `nudgeRightFar`, `nudgeUpFar`, `nudgeDownFar` | the arrows with `shift-` |
| `writeTool` | `w` | `delete` | `delete`, `forward-delete` |
| `toggleSnapping` | `s` | `undo` | `cmd-z` |
| `gridSize` | `g` | `redo` | `cmd-shift-z` |
| `toggleDescription` | `d` | `bringToFront` | `cmd-]` |
| `toggleAllDescriptions` | `shift-d` | `sendToBack` | `cmd-[` |
| `selectParent` | `shift-return` | `followLink` | `l` |
| `selectChildren` | `return` | `back` | `cmd-option-left` |
| `selectAll` | `cmd-a` | `forward` | `cmd-option-right` |
| `copy` | `cmd-c` | `nextScreen` | `cmd-option-down` |
| `paste` | `cmd-v` | `previousScreen` | `cmd-option-up` |
| `duplicate` | `cmd-d` | `toggleSidebar` | `ctrl-cmd-s` |
| `zoomIn` | `cmd-+`, `cmd-=` | `zoomOut` | `cmd--` |
| `actualSize` | `cmd-0` | | |

Holding Option to invert snapping, Escape closing the details panel, and the File menu's commands aren't actions and
can't be rebound. Keybinds stay off while text is being edited, except `undo`, `redo`, `copy`, `paste` and
`selectAll`.
