# Autosave that writes what changed (milestone 18)

How milestone 18 of the [v1 roadmap](../v1-roadmap.md) is built, the second core responsiveness milestone. Builds
on the package format from [m1-file-format.md](m1-file-format.md) and the document shell from
[m3-document-shell.md](m3-document-shell.md). Independent of [m17-edit-scaling.md](m17-edit-scaling.md); either can
ship first.

**Status:** shipped

## Goal

Afterwards an autosave on a large project costs about what the last edits changed, so working in a project with many
screens no longer hitches every time the document saves.

`Document.fileWrapper(ofType:)` calls `ProjectPackage.write`, which encodes the manifest and every screen to JSON and
then compares the bytes with the previous package to learn which files changed. It runs on the main thread. Measured
on `main` (5c62402), release build, Linux cloud VM, one 500-region screen:

| Part of a write | ms |
| --- | ---: |
| Build the screen's `JSONValue` | 0.47 |
| Build it and compare with the previous value | 0.71 |
| Write the value to text (`OrderedJSONWriter`) | 4.4 to 5.3 |

A write of one 5,000-region screen is 34 ms, and every screen pays this on every save whether it changed or not.
`OrderedJSONWriter` builds a new `String` for every line's indent and appends strings scalar by scalar in `quoted`,
which is 12 % of a write on its own.

## Scope

**In:**

- **Unchanged screens skip the text.** `ProjectPackage.write` takes an encoding cache holding, for each file it
  wrote, the `JSONValue` and the bytes. A file whose value equals the cached one reuses the cached bytes and counts
  as unchanged without a byte comparison. Comparing values is exact, so the output is the same bytes as an
  uncached write.
- **A faster writer.** `OrderedJSONWriter` writes UTF-8 bytes into one buffer, indents from a precomputed table,
  and copies a string's bytes in one step when it has nothing to escape.
- **Timings.** `CorePerformanceTests` gains a write of a ten-screen project after editing one region, with and
  without the cache.

**Out:**

- Encoding on a background thread or asynchronous autosave: the model is not safe to read off the main thread.
  Revisit if a save still shows in a profile after this milestone.
- Tracking which screens an edit touched (dirty flags on commands): the value comparison finds them exactly without
  touching every command.
- Reading speed, the Markdown and single-file JSON exports, and the editor-state file beyond going through the same
  cache.
- Any change to the file format, key order or formatting. `Schema/examples/acme.uidesc` must come out byte for byte.

## Steps

| # | Step | Touches | Depends on |
| --- | --- | --- | --- |
| 1 | Faster writer | `Format/OrderedJSONWriter.swift`, `Tests/.../OrderedJSONWriterTests.swift` | none |
| 2 | Encoding cache | `Format/ProjectPackage.swift`, `Tests/.../ProjectPackageTests.swift` | none |
| 3 | The document keeps a cache | `InterfaceDescriber/Document.swift` | 2 |
| 4 | Timings | `Tests/.../CorePerformanceTests.swift`, `Model/StressProject.swift` | none |

Core paths are under `Packages/DescriberCore/Sources/DescriberCore/` and `Packages/DescriberCore/Tests/
DescriberCoreTests/`. Steps 1, 2 and 4 can be built in parallel; land 4 first so the others can be timed.

1. **Faster writer.** `OrderedJSONWriter.data(_:)` writes into a `[UInt8]` reserved to a size estimate and returns
   `Data` from it; `string(_:)` decodes that buffer. Indents come from a table of `"  "` repeats built once.
   `quoted` scans the string's UTF-8 view: with no byte below `0x20`, no `"` and no `\`, it appends the bytes in
   one call; otherwise it escapes byte by byte exactly as today (control characters as `\uXXXX`, the named escapes,
   non-ASCII bytes as they are). Doubles and integers are formatted as today. Covered by the existing
   `OrderedJSONWriterTests`, plus a test that a string with every control character, quotes, backslashes, emoji
   and combining marks writes the same as `JSONSerialization` with `.withoutEscapingSlashes`, and the byte-for-byte
   example test.
2. **Encoding cache.** Add `public final class PackageEncodingCache` holding `[String: (value: JSONValue, data:
   Data)]` by package path. `ProjectPackage.write(project:previous:cache:)` builds each file's value as today; when
   the cache has an equal value for that path and the previous package still holds the cached bytes there (a
   memory compare, which is cheap next to writing the text), it reuses the bytes and puts the path in `unchanged`. Otherwise it writes the value and
   stores it. Paths no longer written are dropped from the cache. `write(project:previous:)` without a cache behaves
   exactly as today. A seeded test applies random commands to a multi-screen project, writing after each with and
   without one long-lived cache, and checks the two results are equal (`tree`, `removed`, `unchanged`) every time.
   Cover a screen rename, which changes link names in other screens' files, and a screen reorder, which can
   change slugs.
3. **The document keeps a cache.** `Document` holds one `PackageEncodingCache`, passes it to every write, and
   replaces it with an empty one in `read(from:ofType:)` and after a revert, since both replace `packageTree`. No
   other app change.
4. **Timings.** `Project.stressTest` gains `screenCount` (default 1, so every existing caller is unchanged), with
   links between screens so names matter. `CorePerformanceTests` prints: writing the 500-region screen with no
   cache; and, on a ten-screen project of 500 regions each, writing after retitling one region, with and without
   a warm cache.

## Done when

**Tests and CI:**

- [ ] The seeded cache test passes: writes with a long-lived cache equal uncached writes after every edit,
  including screen renames and reorders.
- [ ] `quoted` matches `JSONSerialization` on the escaping test string, and every existing `OrderedJSONWriterTests`
  and `ProjectPackageTests` test passes unchanged.
- [ ] `Schema/examples/acme.uidesc` still re-saves byte for byte.
- [ ] `scripts/bench.sh` in a cloud session prints: an uncached write of the 500-region screen under 1.5 ms (from
  3.2 to 4.4), and a cached write of the ten-screen project after retitling one region under a quarter of the
  uncached write of the same project. The PR reports the before and after.
- [ ] `scripts/check.sh` passes (the PR says which stages ran).

**On the Mac:**

- [ ] On a project with ten 500-region screens, editing for a minute shows no hitch when the document autosaves.
- [ ] Save, close and reopen keeps every edit, and the package's files change only for the screens that were edited
  (check the modification dates in Finder).
- [ ] Revert to Saved, then edit and save, writes correctly.

## Open questions

| Question | Default if unanswered | Answer |
| --- | --- | --- |
| Also skip building the value for screens the session didn't touch since the last write? | No: building and comparing is 0.7 ms per 500 regions and exact. Revisit with dirty tracking only if large projects still hitch. | Dallas agreed: the default. |
