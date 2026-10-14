# Indigo

Interface Describer is a macOS app for laying out an app's screens as labeled rectangles on a snapping grid. Each
rectangle is a region with a title, a kind, and a description, and regions can link to other screens. The result
is a `.uidesc` package of plain JSON that lives in a project's docs folder, so agents building the UI can read it.

- Spec: [docs/app-spec.md](docs/app-spec.md)
- Roadmap: [docs/v1-roadmap.md](docs/v1-roadmap.md)
- Conventions for contributors and agents: [CLAUDE.md](CLAUDE.md)

## Running the app

Requirements: macOS 14 or later, Xcode 16, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). Open Xcode once after installing it so it finishes setting up its command line tools.

```sh
git clone https://github.com/dgcrensh/Indigo.git
cd Indigo
xcodegen generate
```

Then either open `InterfaceDescriber.xcodeproj` in Xcode, pick the InterfaceDescriber scheme, and press ⌘R, or
build and launch from the terminal:

```sh
xcodebuild build -project InterfaceDescriber.xcodeproj -scheme InterfaceDescriber -configuration Release \
    -destination 'platform=macOS' -derivedDataPath DerivedData
open "DerivedData/Build/Products/Release/Interface Describer.app"
```

The app opens with a new untitled project. To see a filled-in one, choose File > Open and pick
`Schema/examples/acme.uidesc`. To keep the app, drag `Interface Describer.app` into Applications. It is signed
for local use only, so a copy built on one Mac may need a right-click and Open on another.

The app follows the Mac's light or dark appearance: warm paper in light mode, "night paper" in dark mode. Exported
PNGs always use the light look.

## Building

Requirements: macOS 14, Xcode 16, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/check.sh          # core tests, format check, app icon, app build and tests
scripts/check.sh --core   # core tests and format check only, no Xcode needed
scripts/bench.sh          # time the core work behind canvas events and edits, release build
scripts/bench.sh --profile  # also sample it with perf and list the hottest functions (Linux)
```

`scripts/check.sh --core` and `scripts/bench.sh` run in Claude Code cloud sessions, whose SessionStart hook
(`.claude/hooks/session-start.sh`) installs Swift and perf. The app's own timings (`CanvasPerformanceTests`) need a
Mac.

The app icon is drawn by `swift scripts/render-app-icon.swift`, which writes every size into
`InterfaceDescriber/Assets.xcassets/AppIcon.appiconset`. Run it after changing the palette and commit the PNGs;
`scripts/check.sh` fails if they no longer match what the script draws.

To work in Xcode, run `xcodegen generate` and open `InterfaceDescriber.xcodeproj`. The project file is generated
from `project.yml` and is not committed.
