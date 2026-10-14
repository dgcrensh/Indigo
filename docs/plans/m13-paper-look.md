# Paper look: palette, canvas, tool pill, details card (milestone 13)

How milestone 13 of the [v1 roadmap](../v1-roadmap.md) is built, the first of two Paper studio milestones. Builds on
the canvas renderer from [m4-canvas-rendering.md](m4-canvas-rendering.md), tools and toasts from
[m5-tools-gestures.md](m5-tools-gestures.md), the details panel from [m6-details-panel.md](m6-details-panel.md),
and PNG export from [m11-exports.md](m11-exports.md). [m14-paper-chrome.md](m14-paper-chrome.md) finishes the look
with the sidebar, title bar and app icon.

**Status:** draft

## Goal

Afterwards the app looks like mockup C ("Paper studio"): the screen sits as a soft off-white sheet on a warm paper
desk, regions are tinted by what kind they are, an indigo accent marks selection and the active tool, the tools sit
in a floating pill you can click, and the details panel is a white card. Dark mode is a warm "night paper" version
of the same look, and exported PNGs match the canvas.

## Scope

**In:**

- **Palette in the core.** A Foundation-only `PaperPalette` holding every color of the look as sRGB values, one set
  for light and one for dark, and `KindFamily`, which groups the eleven region kinds into five families:

  | Family | Kinds | Light fill / border / text | Dark fill / border / text |
  | --- | --- | --- | --- |
  | Neutral | open | #F4F1EA / #C7BEAE / #3A332C | #34302B / #5A5248 / #E8E1D6 |
  | Structure | container, list, navigation | #EFECF9 / #B9AEE6 / #3D3470 | #2F2B47 / #6A5FB0 / #D9D3FA |
  | Content | text, image | #DCEAF7 / #8DB4DA / #2E4A66 | #23344A / #4F7AA6 / #CFE2F7 |
  | Action | button, menu-item | #FBE1CC / #E3A97A / #6B3A12 | #45301F / #B07A4C / #F7D9BF |
  | Input | input, toggle, picker | #DDF1E8 / #8CC9AE / #22543F | #1F3A30 / #4E9A7A / #CDEEDF |

  The rest of the palette, light then dark: desk #EAE5DB / #1F1C19; grid dots #D3CBBD / #3A352F; sheet #FFFDF9 /
  #2B2723; sheet border #DDD5C8 / #3F3A33; chrome (panel and window background) #F4F1EA / #26231F; card #FFFFFF /
  #2F2B26; well (field background) #F4F1EA / #24211D; ink #2A2622 / #EDE7DC; secondary ink #6E655B / #A39A8E; accent
  #4A4FD1 / #8C90F0; on-accent (text on an accent fill) #FFFFFF / #1F1C19; outside-the-frame tint #D9534F at 20% in
  both. A builder may nudge a value to pass the contrast tests below, and says so in the PR.
- **Shapes in the core.** `PaperShapes` with the corner radius of a region (6 pt, at most a quarter of its shorter
  side, so small regions don't turn into pills) and of a screen's sheet: 55 pt for the iPhone presets, 18 pt for the
  iPad presets, 12 pt for overlay screens (modal, sheet, popover, menu, alert), and square for laptop, desktop,
  This Device, Custom and user presets. Radii are in screen points and scale with zoom like everything else.
- **Canvas.** `CanvasColors` is rebuilt from `PaperPalette` for the view's appearance, and `RegionLayers` uses it:
  - The desk behind everything, and a dot grid in place of grid lines, shown under the same rule as today (snapping
    on, or the grid popover open).
  - The sheet: rounded per `PaperShapes`, a 1 pt sheet border, and one soft shadow whose `shadowPath` is set so it
    stays cheap. The outside-the-frame tint stays the viewport's rectangle, since the stored viewport is a rectangle;
    only the sheet's drawing is rounded. A scrolling screen's dashed viewport line uses the accent at 60%.
  - Regions: the family's fill, a 1 pt family border, the rounded corner from `PaperShapes`, and the title in the
    family's text color. `text` regions draw no fill, only the border. Descriptions shown with `D` use the family
    text color at 80%.
  - Selection: a 2 pt accent border. Handles are 8 pt circles, card-filled with a 1.5 pt accent ring.
  - The region being drawn and the marquee: a 1 pt dashed accent outline over the accent at 8%.
  - The link indicator becomes an 8 pt accent dot inset 6 pt from the region's top-right corner, replacing the
    arrow glyph. Scroll indicators and the dashed scroll content outline use the accent at 50%.
- **Type.** SF Pro Rounded (the system font with the `.rounded` design) for region titles and descriptions, the
  tool pill, the toast, and the details card. Region titles are semibold.
- **Tool pill.** A floating card-colored capsule centered at the bottom of the canvas, 20 pt from the edge, with a
  soft shadow: Select, Region and Write buttons, a hairline divider, and a snap button reading "Snap 8" (the current
  grid size) that is accent-tinted while snapping is on.
  - Clicking a tool button does exactly what its key does (`choose(_:)`, with the toast); clicking Snap does what
    `S` does. Clicking the snap button with Option held opens the grid popover, as `G` does.
  - The active tool's button is accent-filled with on-accent text; the pill follows tool changes made by key.
  - Clicks on the pill never reach the canvas, and the pill never takes key focus, so keybinds keep working after a
    click on it.
  - Each button has a tooltip naming its key, such as "Region tool (R)", using the current keybinds from settings.
- **Toast** restyled as a small card-colored capsule with ink text and the same shadow as the pill, sitting 12 pt
  above the pill. Timing and behavior unchanged.
- **Details card.** The inspector keeps its split-view slot, slide-in and zoom-to-fit, so its geometry and the
  m6 behavior don't change. Its background becomes chrome, and its content sits in a card inset 12 pt on every
  side, with 16 pt corners and the shadow.
  - Section labels in secondary ink. The title field and description sit on wells (well color, 8 pt corners, no
    border, accent focus ring). The title is 16 pt bold.
  - Kind becomes a wrapping row of chips, one per kind in `RegionKind.allCases` order, each in its family's fill
    and text color, the selected one with a 2 pt accent ring. Choosing a chip performs the same command the pop-up
    did, as one undo step.
  - The chip row is one Tab stop. Left and Right arrows (and Space to choose) move within it, and never reach the
    canvas: no region nudges while the chip row has focus.
  - Links and scrolling rows sit on wells; link rows show an accent dot before the target screen's name.
- **Settings banner and grid popover** restyled as cards: card background, 12 pt corners, the shadow. The banner
  keeps its orange warning icon and border.
- **PNG export** uses the new look in light appearance: desk around the sheet, the rounded sheet and its shadow,
  regions as on the canvas. `ScreenImage.extent` grows by the shadow's reach so the shadow isn't cut off.
- **Dark mode.** Everything above switches between the light and dark palettes when the Mac's appearance changes,
  without reopening the document, as the canvas does today.

**Out:**

- The sidebar, title bar, screen thumbnails and app icon: [m14-paper-chrome.md](m14-paper-chrome.md).
- The dashed arrow from a linked region to its target's name, shown in the mockup. It's closer to the overlay
  preview on the spec's roadmap than to styling, and gets its own plan if wanted.
- Following the Mac's accent color, user-chosen colors or themes in `settings.json`, or a light/dark switch inside
  the app. The look follows the Mac's appearance only.
- Bundled fonts (Figtree in the mockup). SF Pro Rounded ships with macOS.
- New animations. Existing ones (panel slide, zoom-to-fit, toast fade) keep their timings.
- Dark PNG exports. Exports stay light (m11).
- Any change to the file format, the example project, or `settings.json`.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Palette, kind families and contrast | `…/Style/PaperPalette.swift`, `…/Style/KindFamily.swift`, `…/Style/Contrast.swift` | none |
| 2 | Corner radii | `…/Style/PaperShapes.swift` | none |
| 3 | Canvas colors, shapes and type | `InterfaceDescriber/CanvasColors.swift`, `InterfaceDescriber/RegionLayers.swift`, `InterfaceDescriber/CanvasView.swift`, `InterfaceDescriber/PaperStyle+AppKit.swift` | 1, 2 |
| 4 | Tool pill and toast | `InterfaceDescriber/ToolPill.swift`, `InterfaceDescriber/ToastView.swift`, `InterfaceDescriber/CanvasViewController.swift` | 3 |
| 5 | Details card and kind chips | `InterfaceDescriber/DetailsPanelController.swift`, `InterfaceDescriber/KindChips.swift` | 3 |
| 6 | Banner, popover and PNG export | `InterfaceDescriber/SettingsBanner.swift`, `InterfaceDescriber/GridSizePopover.swift`, `InterfaceDescriber/ScreenImageRenderer.swift`, `…/Export/ScreenImage.swift` | 3 |
| 7 | README and roadmap | `README.md`, `docs/v1-roadmap.md`, this plan's Status | 4, 5, 6 |

`…` is `Packages/DescriberCore/Sources/DescriberCore`.

1. **Palette.** `struct PaperColor { red, green, blue, alpha }` (0–1, sRGB) with a hex initializer; `enum
   PaperAppearance { case light, dark }`; `struct PaperPalette` with the named colors above and
   `static func palette(for: PaperAppearance)`; `enum KindFamily: CaseIterable { neutral, structure, content,
   action, input }` with `RegionKind.family` and `PaperPalette.colors(for: KindFamily) -> (fill, border, text)`;
   `Contrast.ratio(_:_:)` using the WCAG 2 relative-luminance formula. Tests, in both appearances: every
   `RegionKind` has a family and the table's grouping holds; each family's text on its fill is at least 4.5:1; ink
   on the sheet, card, chrome and well, and secondary ink on chrome and card, are at least 4.5:1; the accent on the
   sheet and on the card is at least 3:1 (non-text UI); on-accent on the accent is at least 4.5:1 (the active tool
   button); `text` regions' border on the sheet is at least 1.5:1 so an unfilled region is still visible.
2. **Shapes.** `PaperShapes.regionCornerRadius(width:height:)` and `PaperShapes.sheetCornerRadius(for: Screen)`.
   Tests: a large region gets 6; a 4 × 20 region gets 1; an iPhone 15 screen gets 55, an iPad 18, a menu overlay
   12, Laptop, This Device, Custom and a user preset 0; a screen whose preset is unknown gets 0.
3. **Canvas.** `PaperStyle+AppKit.swift` converts `PaperColor` to `CGColor`/`NSColor` and picks the palette from an
   `NSAppearance` (dark when its best match is `.darkAqua`). `CanvasColors` gains per-family fills, borders and title
   colors, desk, dots, sheet border, sheet shadow and accent, all from the palette; the system-color list goes away.
   `RegionLayers.apply` picks colors by the region's family and sets `cornerRadius` from step 2; the title font
   becomes rounded semibold and `TitleWidths` keeps measuring with the same font object. `CanvasView` draws the
   rounded sheet with its shadow, the dot grid (a pattern of dots at grid intersections, drawn as one layer like
   the current grid path), round handles, the accent dot link indicator, and the dashed new-region and marquee
   outlines. App tests: in light and dark appearance a button region's layer uses the action family's fill and a
   `text` region has a clear fill; an iPhone screen's sheet has a 55 pt radius at 100% zoom and 27.5 at 50%;
   handles are circles; the grid layer shows dots exactly when it showed lines before; switching the view's
   appearance re-colors existing region layers. The m12 `CanvasPerformanceTests` 500-region timings still pass.
4. **Tool pill.** `ToolPill` (an `NSView` of `NSButton`s), owned by `CanvasViewController` and placed in the same
   container as the toast; the toast's bottom constraint moves to sit above it. The controller updates the pill
   whenever the tool, snapping or grid size changes, whatever caused it. App tests: clicking the Region button
   sets the tool to Region and shows the "Region tool" toast; pressing `W` highlights Write in the pill; clicking
   Snap toggles snapping and its tint; Option-clicking Snap opens the grid popover; after clicking a pill button the
   canvas is still first responder and `V` switches tools; a mouse-down on the pill starts no marquee; tooltips name
   rebound keys after a settings change.
5. **Details card.** The card container, wells, and `KindChips` (an `NSView` with a chip per kind that accepts first
   responder once, handles Left, Right and Space, and reports the chosen kind to the controller's existing kind
   action). `kindPopUp` is removed and the Tab order becomes title, description, kind chips, links, scrolling. App
   tests (extend `DetailsPanelTests`): clicking the Image chip sets the region's kind to image as one undo step;
   with the chip row focused, Right moves to the next kind and Space chooses it; Right with the chip row focused
   doesn't move the region; Tab from the description lands on the chip row and Tab again on the links; Return,
   Escape and blank-title behavior from m6 are unchanged (the existing tests pass unmodified).
6. **Banner, popover, export.** Restyle the banner and the grid popover. `ScreenImageRenderer` draws the desk, the
   rounded sheet with its shadow and the regions with the light palette; `ScreenImage.extent` gains a margin equal
   to the shadow's blur plus offset on each side. Core test: the extent of a screen whose regions fit is its bounds
   plus the shadow margin. App tests (extend `ExportTests`): a PNG's corner pixel is desk-colored and its center is
   sheet-colored; a button region's pixels are the action fill; exporting in dark appearance still gives the light
   palette.
7. **Docs.** A README line that the app follows the Mac's light or dark appearance. This plan's Status and the
   roadmap row move to shipped.

## Done when

**Tests and CI:**

- [ ] (Core) Every region kind belongs to exactly the family in the table, in both appearances.
- [ ] (Core) Every text color in the palette passes 4.5:1 on the surfaces it sits on, the accent passes 3:1 on the
  sheet and card, and on-accent passes 4.5:1 on the accent, in light and dark.
- [ ] (Core) Region and sheet corner radii follow the rules above, including the small-region cap and square
  sheets for desktop, Custom and unknown presets.
- [ ] (App) Regions draw in their family's colors with rounded corners, `text` regions have no fill, and changing
  the appearance re-colors the canvas without reopening.
- [ ] (App) The tool pill switches tools and snapping by click, follows key changes, never takes focus, and never
  starts a canvas gesture.
- [ ] (App) Kind chips set the kind as one undo step, are one Tab stop, and their arrow keys never nudge a region.
- [ ] (App) Exported PNGs use the light Paper look, sheet shadow included, in either appearance.
- [ ] (App) The m12 500-region timings still pass.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Open the example project: the Login screen is a rounded off-white sheet on a warm dotted desk, the form is
  lavender, the fields mint, the buttons peach, the logo blue, and Forgot password has an indigo dot.
- [ ] Click Region in the pill, draw a region, pick Button from the chips: the region turns peach, and one Undo
  sets it back to open.
- [ ] Press `V`, `R`, `W`: the pill follows, and the toast appears just above it.
- [ ] Switch the Mac to dark mode with the document open: the canvas, pill, card and banner turn to night paper,
  and every title stays readable.
- [ ] Open Debug > New 500-Region Document and drag the whole selection: it feels as smooth as before.
- [ ] Export PNGs at 2× in dark mode: they're light, with rounded sheets and their shadow intact.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Fixed indigo accent, or the Mac's accent color? | Fixed indigo | Fixed indigo (Dallas, 2026-10-14) |
| Night paper dark mode, or always light? | Night paper | Night paper (Dallas, 2026-10-14) |
| SF Pro Rounded, or bundle Figtree? | SF Pro Rounded | SF Pro Rounded (Dallas, 2026-10-14) |
| Kind families, or a color per kind? | Five families | Five families (Dallas, 2026-10-14) |
| The mockup's dashed link arrow in scope? | No, a later feature | No (Dallas, 2026-10-14) |
| Does the outside-the-frame tint follow the sheet's rounded corners? | No. It marks the viewport rectangle, which is what's stored; only the sheet's drawing is rounded. | |
| Does the pill hide while the details card is open? | No. It stays, centered in the canvas area left of the card. | |
