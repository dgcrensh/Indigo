# Data model and file format (milestone 1)

How milestone 1 of the [v1 roadmap](../v1-roadmap.md) is built. Builds on [m0-scaffold.md](m0-scaffold.md).

**Status:** shipped

## Goal

Afterwards a `.uidesc` package written by hand or by an agent can be read into the model and written back out
exactly as spec Section 3 describes, and an example project in the repo proves it re-saves byte for byte.
Nothing is visible in the app yet; this is the format every later milestone saves through.

## Scope

**In:**

- Model types for project, screen, region, link, viewport, scroll, and editor state (spec Sections 2 and 3).
- An ordered JSON writer that produces the spec's key order and formatting.
- Reading with validation and readable errors, including the `schemaVersion` check.
- Package reading and writing as an in-memory file tree, with screen-file slugs and renames.
- A JSON Schema for `project.json` and screen files, and an example project.

**Out:**

- `FileWrapper` and `NSDocument` (milestone 3). The core's file tree is converted to `FileWrapper` there.
- Edit operations and undo (milestone 2). Model properties are settable here, but nothing outside tests
  mutates them yet.
- Exports (milestone 11), even though they read the same model.
- Format migration (spec Section 14). A different `schemaVersion` is an error, nothing more.
- The `references/` folder (spec Roadmap). The writer neither creates nor deletes it.
- App settings (milestone 10). `settings.json` is a different file with its own plan.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Model types | `Packages/DescriberCore/Sources/DescriberCore/Model/…` | none |
| 2 | Ordered JSON writer | `…/Format/OrderedJSONWriter.swift` | none |
| 3 | Encoding the model | `…/Format/ProjectEncoding.swift` | 1, 2 |
| 4 | Decoding and validation | `…/Format/ProjectDecoding.swift`, `…/Format/FormatError.swift` | 1 |
| 5 | Package tree and slugs | `…/Format/ProjectPackage.swift`, `…/Format/Slug.swift` | 3, 4 |
| 6 | Schema and example project | `Schema/uidesc-1.schema.json`, `Schema/README.md`, `Schema/examples/acme.uidesc/…` | 5 |
| 7 | Round-trip and check-script wiring | `…/Tests/DescriberCoreTests/…`, `scripts/check.sh` | 5, 6 |

1. **Model types.** `Project` and `Screen` are `@Observable` final classes; `Region` is a final class so the
   canvas can hold identity; `Link`, `Viewport`, `Scroll`, `Frame` are structs. Fields follow spec 3.2 and 3.3.
   `ScreenKind` (`screen, modal, sheet, popover, menu, alert`), `RegionKind` (the eleven kinds in spec 3.4,
   `open` included), `ScrollAxis`. Frames are `Int` points with absolute coordinates. IDs are `ScreenID` and
   `RegionID` wrappers over lowercase UUID strings. `VariantGroup` holds a name and screen IDs. `EditorState`
   holds per-screen zoom, pan, grid size and scroll offsets, per-region description visibility, and the last
   active screen. Remove the milestone 0 placeholder type.
2. **Ordered JSON writer.** `OrderedJSONWriter` writes a small `JSONValue` enum whose objects are arrays of
   key-value pairs, so key order is whatever the caller gives. Output: 2-space indent, `"key": value`, one key
   per line, empty arrays and objects as `[]` and `{}`, integers without a decimal point, strings escaped as
   `JSONSerialization` would, a trailing newline. Tests pin the exact bytes for each case.
3. **Encoding the model.** Builds `JSONValue` from the model in the spec's key order: regions
   `id, title, kind, x, y, w, h, description, scroll, linksTo, children`; screens
   `id, name, kind, viewport, scroll, regions`; manifest `schemaVersion, name, units, screens, variantGroups`.
   Omits empty `children`, empty `linksTo`, nil `scroll`, `kind: "open"`, and an empty `variantGroups`.
   Writes the derived `screenName` on each link and `name`/`file` on each manifest entry from the current
   model. Tests cover each omission rule and the derived fields after a rename.
4. **Decoding and validation.** Decodes with `JSONDecoder` into private DTOs, then builds the model.
   `FormatError` cases, each with a message naming the file: unsupported `schemaVersion` (checked before
   anything else is read), malformed JSON, a manifest entry whose file is missing, a screen file whose `id`
   doesn't match its manifest entry, a link to an unknown screen ID, a duplicate ID, an unknown kind. Derived
   fields are ignored on read. A missing or unreadable `.editor-state.json` gives default editor state, never an
   error. One test per error case.
5. **Package tree and slugs.** `ProjectPackage` converts between the model and a `PackageTree`
   (`[String: Data]` keyed by relative path). `Slug.make(_:)` lowercases, turns runs of non-alphanumerics into
   `-`, and trims dashes; an empty result becomes `screen`. Collisions get `-2`, `-3`, and so on, in sidebar
   order. `write(project:previous:)` returns the new tree plus the set of paths to remove, so a renamed screen
   moves its file and a deleted screen's file is removed, and unchanged screen files are reported as unchanged
   so the app can skip rewriting them. Tests: rename, delete, collision, unchanged detection, a package with an
   extra unknown file (left alone).
6. **Schema and example project.** `Schema/uidesc-1.schema.json` (JSON Schema 2020-12) describes
   `project.json` and screen files, including the kind enums and the scroll object, with `additionalProperties:
   false` on regions and screens. `Schema/README.md` explains the package layout in a page, for agents and
   humans, and links to spec Section 3. `Schema/examples/acme.uidesc/` holds a project with a Login screen, a
   Login (Desktop) variant, Reset Password, a Settings screen with a vertically scrolling list region, and an
   account menu overlay, with nested regions and links between them. It is written by the encoder, not by hand.
7. **Round-trip and check-script wiring.** A test reads `Schema/examples/acme.uidesc`, writes it, and asserts
   every file is byte-for-byte identical. A test validates every JSON file in the example against the schema
   (using a small validator dependency if one is acceptable, see Open questions). `scripts/check.sh` gains a
   stage that runs these two tests by name, so a failure names the example project.

## Done when

**Tests and CI:**

- [ ] `OrderedJSONWriter` tests pin exact output bytes for nested objects, empty containers, integers, and escaped strings.
- [ ] Encoding a region with no kind, no children, no links, and no scroll writes none of those keys.
- [ ] Encoding writes keys in the spec order for regions, screens, and the manifest.
- [ ] After renaming a screen in the model, the written manifest entry and every link's `screenName` use the new name, and the old screen file is in the remove set.
- [ ] Reading a package with `schemaVersion: 2` throws the unsupported-version error and reads no screen files.
- [ ] Each `FormatError` case has a test.
- [ ] Two screens named "Login" are written as `login.json` and `login-2.json`.
- [ ] `Schema/examples/acme.uidesc` re-saves byte for byte.
- [ ] Every JSON file in the example validates against `Schema/uidesc-1.schema.json`.
- [ ] `scripts/check.sh` passes.

**On the Mac:**

- [ ] `Schema/examples/acme.uidesc` shows as one document in Finder.
- [ ] Opening the example's screen files in a text editor shows the layout in spec Section 3.3, readable without the app.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Is a JSON Schema for the format wanted in v1? It isn't in the spec, but helps agents write valid files. | Yes, as in step 6. | |
| May the core take a test-only dependency for schema validation? | Yes, a test-only dependency on a JSON Schema validator package; the library itself keeps no dependencies. | Built without one: the only maintained Swift validator pins its own dependencies by revision, which SwiftPM rejects for versioned use, so the tests carry a small validator for the keywords the schema uses. |
| Should `units` stay in `project.json` even though it is always `points`? | Yes, as in spec 3.2. | |
