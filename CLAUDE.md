# Conventions for agents building Indigo

Indigo is Interface Describer, a macOS 14+ app for describing app interfaces as labeled regions on screens. The
spec is [docs/app-spec.md](docs/app-spec.md) and the build order is [docs/v1-roadmap.md](docs/v1-roadmap.md).

## Layout

- `Packages/DescriberCore/`: the core Swift package. Data model, file format, commands, layout rules, exports.
  Foundation only: no AppKit, SwiftUI, or `FileWrapper`, so its tests run anywhere with a Swift toolchain.
- `InterfaceDescriber/`: the macOS app target. AppKit canvas, SwiftUI panels, `NSDocument`.
- `InterfaceDescriberTests/`: app unit tests.
- `project.yml`: the XcodeGen definition. The `.xcodeproj` is generated and never committed; run
  `xcodegen generate` after pulling or after adding files.
- `Schema/`: JSON Schema for the `.uidesc` format and the example project.
- `docs/`: spec, roadmap, plan template, and one plan per milestone in `docs/plans/`.

## Rules

- **Logic goes in `DescriberCore` with tests.** Rules from the spec (parenting, snapping, key order, slugs,
  validation) live in the core and are covered by `DescriberCoreTests`. The app stays a thin layer that draws,
  routes input, and calls the core.
- **Every edit goes through a command** (from milestone 2). The app never mutates the model directly; it performs
  a `Command` on the `EditSession`, so undo, redo, and tests see every change.
- **`scripts/check.sh` must pass before a PR is ready.** It runs core tests, the format check, and the app build
  and tests. Without Xcode, `scripts/check.sh --core` runs the first two; say in the PR which stages you ran.
- **The example project re-saves byte for byte** (from milestone 1). `Schema/examples/acme.uidesc` must come
  out of a read and write unchanged. If the format changes on purpose, regenerate the example with the encoder
  in the same PR.
- **Plans follow plan, review, build.** Write a plan from `docs/plan-template.md`, get it reviewed, then build
  it. One plan is one PR. Check the PR against the plan's "Done when" list and report each line.
- **Update a plan's Status line in the PR that ships it,** and its row in the roadmap's milestone table.
- **Formatting** follows `.swift-format` (4 spaces, 120 columns). `swift format --in-place --recursive
  Packages/DescriberCore/Sources Packages/DescriberCore/Tests InterfaceDescriber InterfaceDescriberTests` fixes
  most findings.
