# Exports: Markdown, single-file JSON, PNG (milestone 11)

How milestone 11 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on the format from
[m1-file-format.md](m1-file-format.md) and the canvas renderer from [m4-canvas-rendering.md](m4-canvas-rendering.md),
with link indicators from [m8-screens-links.md](m8-screens-links.md) and scroll drawing from
[m9-scrolling.md](m9-scrolling.md).

**Status:** shipped

## Goal

Afterwards File > Export writes the project three ways for readers that can't open a package (spec Section 11): one
Markdown outline of every screen, one JSON file holding the manifest and every screen inline, and a PNG of each
screen at 1× or 2×. The package stays the canonical format; exports are written only when asked for, never on save
(roadmap D3).

## Scope

**In:**

- `MarkdownExport` in the core: one `.md` for the whole project.
  - A `#` heading with the title (the document's name in the app, the project's name otherwise), a line saying how
    many screens there are and how to read positions, and a list linking to every screen.
  - A `##` section per screen in sidebar order, its heading the screen's name, with its kind, its viewport (preset
    name and size), its scrolling when it scrolls, and its variants (the other screens of its group, linked).
  - Then the screen's regions as a nested list, back to front as they draw: bold title, kind (left out when open), `x`,
    `y` and size in points, the description, the scrolling, and each link as an in-document anchor to the target's
    section with its trigger. A screen with no regions says so.
  - Anchors follow GitHub's heading IDs (lowercase, punctuation dropped, spaces to `-`, repeats get `-1`, `-2`), so
    links work on GitHub and in editors that use the same rule. Titles and names are escaped so `*`, `_`, `[` and
    friends show as typed. A link to a screen that no longer exists names the missing ID instead of linking.
- `ProjectJSONExport` in the core: one `.json` with `schemaVersion, name, units, screens, variantGroups`, where each
  `screens` entry is the whole screen object exactly as its screen file writes it (same key order, same omissions,
  same `screenName`s), and no editor state. Written with `OrderedJSONWriter`, so it has the package's formatting.
- The schema gains an `export` shape for that file, and `Schema/README.md` describes both exports.
- Golden files `Schema/examples/acme.md` and `Schema/examples/acme.json`, written from the example project by the
  same `REGENERATE_EXAMPLE=1` test that writes the package, and checked by `scripts/check.sh` like the package.
- `ScreenImage` in the core: the area a screen's PNG covers (the canvas bounds plus every part of a region drawn
  outside them, after scrolling and clipping), and PNG file names (screen slugs as in the package, with `@2x` at
  2×).
- `ScreenImageRenderer` in the app: renders one screen with the canvas's own `RegionLayers` into a bitmap at 1× or
  2×, in the light appearance whatever the Mac uses. It draws what the canvas draws apart from editing aids: the
  bounds, the dashed viewport line of a scrolling screen, regions with truncated titles, link indicators, scroll
  indicators, tints on parts outside the bounds, and descriptions for the regions showing them (`D`). Regions inside
  scrolling content are drawn at their saved scroll positions and clipped as on the canvas. No selection, handles,
  grid or toasts.
- File > Export submenu with Markdown…, Single-File JSON… and PNG Images…:
  - Markdown and JSON open a save panel in the package's folder (the Desktop's default for an unsaved document)
    named after the document, such as `Acme.md`.
  - PNG Images… opens a folder panel with a Scale pop-up (1× or 2×, 2× by default) and writes every screen's PNG
    into the chosen folder, replacing files of the same name.
  - An error writing shows an alert on the window.
  - Exports read the project as it is, including a region being typed in the details panel, and record nothing to
    undo.

**Out:**

- PNGs inside the package or written on save (roadmap D3).
- Exporting one screen or a selection, a choice of which screens, or exporting from the command line (the agent CLI
  is on the spec's roadmap).
- Reading an export back in. The package is the only format the app opens.
- Backlinks ("opened from") in the Markdown and the fractional layout view (spec Section 15).
- Dark-appearance PNGs or a transparent background.
- Renaming the project to match the document. The Markdown's title uses the document's name instead.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Markdown export and anchors | `…/Export/MarkdownExport.swift`, `…/Export/MarkdownText.swift` | none |
| 2 | Single-file JSON export, schema and golden files | `…/Export/ProjectJSONExport.swift`, `Schema/uidesc-1.schema.json`, `Schema/README.md`, `Schema/examples/acme.md`, `Schema/examples/acme.json` | 1 |
| 3 | Image area and file names | `…/Export/ScreenImage.swift` | none |
| 4 | Rendering screens to PNG | `InterfaceDescriber/ScreenImageRenderer.swift`, `InterfaceDescriber/CanvasColors.swift` | 3 |
| 5 | The Export menu and panels | `InterfaceDescriber/ExportController.swift`, `InterfaceDescriber/MainMenu.swift`, `InterfaceDescriber/DocumentWindowController.swift` | 1, 2, 4 |

1. **Markdown.** `MarkdownExport.markdown(for:title:) -> String` and `MarkdownText` (escaping, GitHub heading
   anchors with repeats). Tests: anchors for plain, punctuated, accented and repeated names, including a screen
   named like the title; escaping; a region without a kind, with a multi-line description, with two links, with a
   link to a missing screen; a screen with no regions; a scrolling screen and region; variants listed on both
   screens of a group.
2. **JSON and golden files.** `ProjectJSONExport.json(for:)` and `data(for:)`. Tests: each inline screen equals
   `ProjectEncoding.screen` for that screen; no `variantGroups` when there are none; no `file` keys; the export of
   the example validates against the schema and the schema rejects a manifest-style entry in it; both golden files
   are what the exporters write from `AcmeExample`, and `testRegenerateExample` rewrites them.
3. **Image area.** `ScreenImage.extent(of:offsets:)` and `ScreenImage.fileNames(for:scale:)`. Tests: a screen whose
   regions fit is its canvas bounds; a region past the right edge widens it; a child scrolled out of its parent's
   frame doesn't; repeated names get `-2`; `@2x` at 2×.
4. **Rendering.** `ScreenImageRenderer.pngData(for:in:scale:)` and `image(for:in:scale:)`. Builds a layer tree with
   geometry flipped, puts each clipped region in a container that masks to its bounds (`render(in:)` ignores
   `mask`), and renders it into a bitmap context scaled by `scale`. `RegionLayers` is used as it is, given no clip;
   `CanvasColors` gains the background outside the bounds. App tests: pixel size is the extent times
   the scale; a region's fill shows inside it and the background outside the bounds; the title draws at the top of a
   tall region, not the bottom; a shown description adds ink that a hidden one doesn't; a child scrolled below its
   list's frame is not drawn.
5. **Export menu.** `ExportController` (owned by the window controller) with `writeMarkdown(to:)`, `writeJSON(to:)`,
   `writePNGs(to:scale:)` and the panels that call them. `DocumentWindowController` gains `exportMarkdown(_:)`,
   `exportJSON(_:)` and `exportPNGs(_:)`. App tests: the File menu has the three items; each writer produces the
   core's output or one PNG per screen with the right names and sizes; the Markdown title is the document's name.

## Done when

**Tests and CI:**

- [ ] (Core) The Markdown export of the example project is `Schema/examples/acme.md`, and every link in it points
  at a heading that exists in it.
- [ ] (Core) Anchors match GitHub's for punctuated, accented and repeated names, and titles are escaped.
- [ ] (Core) The single-file JSON export of the example is `Schema/examples/acme.json`, matches the schema, and each
  screen in it is identical to that screen's file.
- [ ] (Core) The image area covers parts of regions outside the bounds and ignores content scrolled out of view.
- [ ] (App) A screen's PNG is its image area at 1× and at 2×, with titles at the top of regions, descriptions only
  where shown, and clipped content left out.
- [ ] (App) The File > Export items write Markdown, JSON, and one PNG per screen named by slug.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] Open the example and choose File > Export > Markdown…: the file opens in a Markdown viewer with one section
  per screen, and clicking Forgot password's link jumps to Reset Password.
- [ ] Export > Single-File JSON…: the file holds all five screens, and pasting it into a chat lets it answer
  questions about any screen.
- [ ] Export > PNG Images… at 2×: five PNGs, crisp on a Retina display, matching what the canvas shows with
  descriptions toggled on for the regions showing them; Settings shows its list scrolled as it was left.
- [ ] Switch the Mac to dark mode and export again: the PNGs are still light.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Which screens does PNG export write? | All of them, one file each. Single-screen export can come later. | |
| Light or the Mac's appearance for PNGs? | Always light, so images look the same whoever exports them. | |
| What is the Markdown title? | The document's name (`Acme` for `Acme.uidesc`), since the project's stored name stays "Untitled" for new documents. | |
| Do region kinds show when open? | No, as in the file; the intro line says a region without a kind is open. | |
