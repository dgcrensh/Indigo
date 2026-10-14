# Paper chrome: sidebar cards, title bar, app icon (milestone 14)

How milestone 14 of the [v1 roadmap](../v1-roadmap.md) is built, the second of two Paper studio milestones. Builds on
the palette, shapes and card style from [m13-paper-look.md](m13-paper-look.md) and the sidebar from
[m8-screens-links.md](m8-screens-links.md).

**Status:** shipped

## Goal

Afterwards the window around the canvas matches the Paper look: the sidebar shows each screen as a white card with a
live thumbnail of its regions, the title bar blends into the paper and names the current screen, and the app has
its own icon in the Dock and Finder.

## Scope

**In:**

- **Thumbnails in the core.** `ScreenThumbnail.rects(for:fitting:)` turns a screen into the rectangles a small
  preview draws: the sheet scaled to fit a box (aspect kept, centered), then each region's frame scaled the same
  way with its `KindFamily`, back to front as the canvas draws them. Regions inside scrolling content are placed at
  scroll offset zero and clipped to their scrolling parent's frame. Regions smaller than half a point at the
  thumbnail's size are dropped, and at most 300 rectangles are kept (the topmost, since they cover the rest), so a
  500-region screen stays cheap.
- **Sidebar cards.** The SwiftUI sidebar keeps its list, selection, drag to reorder, context menus, inline rename,
  and the active screen's settings underneath. Its look changes:
  - The background is chrome. Each screen row is a card (card color, 12 pt corners, the m13 shadow), 8 pt apart,
    with a thumbnail on the left and the name (semibold) and viewport short name (secondary ink) on the right.
    Overlay screens add their kind, such as "Menu · 240 × 180".
  - The thumbnail is drawn with SwiftUI `Canvas` from `ScreenThumbnail`: sheet color with its corner radius scaled
    from `PaperShapes`, family fills for regions (no rounding at this size), in a 40 × 72 pt box.
  - The selected screen's card gets a 2 pt accent ring instead of the system selection highlight.
  - A variant group shows as a header line in secondary ink with its member cards indented 10 pt under it, as now.
  - Under the last card, a dashed "New Screen" card runs the existing New Screen action.
  - The active screen's settings (kind, viewport, scrolling) move into a card at the bottom of the sidebar, with
    the m13 wells.
- **Thumbnail updates.** A screen's thumbnail redraws after an edit to that screen, at most every 0.3 s, and not
  during a drag gesture (it catches up when the drag ends). Other screens' thumbnails aren't recomputed. Thumbnails
  follow the Mac's appearance like everything else.
- **Title bar.** The title bar is transparent over the chrome color (`titlebarAppearsTransparent`), with the
  document's name as the title and the active screen's name as the window's subtitle, updated on screen switches
  and renames. The sidebar toggle and the existing title-bar behavior (proxy icon, rename, Revert menu) keep
  working.
- **App icon.** A paper sheet tilted slightly on an indigo ground, carrying three pastel regions (structure, input,
  action families) with an indigo selection ring on one. Drawn by a Swift script, `scripts/render-app-icon.swift`,
  using Core Graphics and the palette values, so it can be redrawn when the palette changes. It writes every size
  of `InterfaceDescriber/Assets.xcassets/AppIcon.appiconset` (16 to 1024 at 1× and 2×) and its `Contents.json`.
  The PNGs are committed. `project.yml` adds the asset catalog and `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`;
  `Info.plist` gains `CFBundleIconName`.

**Out:**

- Anything on the canvas, the details card or the tool pill: [m13-paper-look.md](m13-paper-look.md).
- A document icon for `.uidesc` packages in Finder. Can follow once the name and extension are final (roadmap D5).
- Thumbnails in exports, in the package, or anywhere but the sidebar.
- Showing descriptions or titles in thumbnails.
- Changing what the sidebar can do: no new actions, sorting, search or filters.
- A toolbar. The tool pill from m13 carries the tools.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Thumbnail geometry | `…/Style/ScreenThumbnail.swift` | m13 step 1, 2 |
| 2 | Sidebar cards and thumbnails | `InterfaceDescriber/ScreenSidebar.swift`, `InterfaceDescriber/ScreenThumbnailView.swift`, `InterfaceDescriber/DocumentModel.swift` | 1 |
| 3 | Title bar | `InterfaceDescriber/DocumentWindowController.swift` | none |
| 4 | App icon | `scripts/render-app-icon.swift`, `InterfaceDescriber/Assets.xcassets/…`, `project.yml`, `InterfaceDescriber/Info.plist` | none |
| 5 | README and roadmap | `README.md`, `docs/v1-roadmap.md`, this plan's Status | 2, 3, 4 |

`…` is `Packages/DescriberCore/Sources/DescriberCore`.

1. **Thumbnail geometry.** `struct ThumbnailRect { frame: (x, y, w, h in thumbnail points), family: KindFamily }`
   and `ScreenThumbnail.rects(for: Screen, fitting: (width, height)) -> (sheet: frame, sheetRadius, regions:
   [ThumbnailRect])`. Tests: a 393 × 852 screen in a 40 × 72 box is 33.2 × 72 and centered horizontally; a region at
   the screen's center lands at the box's center; order is back to front; a child scrolled out of its list's frame
   is clipped to the list; a 2 × 2 pt region on a desktop screen is dropped; a 500-region screen yields at most 300
   rectangles and they are the topmost ones; computing the 500-region fixture takes under 2 ms in a test build.
2. **Sidebar.** `ScreenThumbnailView` draws the rectangles with `Canvas`. `DocumentModel` gains a per-screen
   thumbnail revision that bumps after an edit to that screen, throttled to 0.3 s and held while a gesture is in
   progress; each card reads only its own screen's revision so other cards don't redraw. `ScreenSidebar` rows become
   cards, the selection ring replaces the list highlight, the New Screen card and the settings card are added. App
   tests (extend `ScreenManagementTests`): the sidebar shows one card per screen with the right name and viewport
   label; editing a region on Login bumps Login's thumbnail revision once after the throttle and not Settings';
   dragging a region bumps nothing until the drag ends; the New Screen card adds a screen as one undo step; drag
   reorder, rename and context menu tests from m8 pass unmodified.
3. **Title bar.** Set the window's title bar transparent and its background to chrome; keep the title from
   `NSDocument`; set `subtitle` to the active screen's name whenever it changes. App tests: the subtitle is the
   active screen's name, follows Next Screen and a rename, and is empty for a project with no screens.
4. **App icon.** The script runs with `swift scripts/render-app-icon.swift` and writes the icon set; running it twice
   produces identical files. App test: the built app's bundle has an `AppIcon` (`NSImage(named:
   NSImage.applicationIconName)` is not the generic icon, checked by its size representations).
5. **Docs.** README notes the icon script under Building. This plan's Status and the roadmap row move to shipped.

## Done when

**Tests and CI:**

- [ ] (Core) Thumbnails keep the screen's aspect, center it, draw back to front, clip scrolled content, drop
  sub-half-point regions, and cap at the 300 topmost.
- [ ] (Core) A 500-region thumbnail computes in under 2 ms.
- [ ] (App) The sidebar shows a card per screen, and only the edited screen's thumbnail updates, throttled and held
  during drags.
- [ ] (App) The window's subtitle is the active screen's name and follows switches and renames.
- [ ] (App) The app bundle has its own icon, and the icon script is deterministic.
- [ ] (App) The m8 sidebar tests and m12 500-region timings still pass.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Open the example project and show the sidebar (Ctrl-Cmd-S): each screen is a card with a recognizable
  miniature, Login and its desktop variant grouped, Account menu labeled as a menu.
- [ ] Draw a region on Login: its thumbnail picks it up a moment later; other cards don't flicker.
- [ ] Drag-reorder two cards and rename one from the context menu: both work as before, and the title bar subtitle
  follows the rename.
- [ ] Switch to dark mode: cards, thumbnails and the title bar turn to night paper.
- [ ] The Dock and Finder show the new icon after a fresh build.
- [ ] Debug > New 500-Region Document with the sidebar open: dragging the selection stays smooth.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| One plan or two for the Paper look? | Two: m13 the canvas, m14 the chrome. | Two (Dallas, 2026-10-14) |
| Thumbnail size? | 40 × 72 pt box, the mockup's proportions. Wide screens get a short, wide thumbnail in the same box. | |
| Does the icon need a designer's pass before v1 ships? | No. The drawn icon ships; a hand-made one can replace the PNGs later. | |
