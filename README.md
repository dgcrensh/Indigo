# Indigo

Interface Describer is a macOS app for laying out an app's screens as labeled rectangles on a snapping grid. Each
rectangle is a region with a title, a kind, and a description, and regions can link to other screens. The result
is a `.uidesc` package of plain JSON that lives in a project's docs folder, so agents building the UI can read it.

- Spec: [docs/app-spec.md](docs/app-spec.md)
- Roadmap: [docs/v1-roadmap.md](docs/v1-roadmap.md)
- Conventions for contributors and agents: [CLAUDE.md](CLAUDE.md)

## Building

Requirements: macOS 14, Xcode 16, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/check.sh          # core tests, format check, app build and tests
scripts/check.sh --core   # core tests and format check only, no Xcode needed
```

To work in Xcode, run `xcodegen generate` and open `InterfaceDescriber.xcodeproj`. The project file is generated
from `project.yml` and is not committed.
