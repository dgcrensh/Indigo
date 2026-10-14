#!/usr/bin/env bash
# Runs every check a PR must pass, in order, stopping at the first failure.
#
#   scripts/check.sh           core tests, format check, app build and tests
#   scripts/check.sh --core    core tests, example project, and format check only (no Xcode needed)
#   scripts/check.sh --no-app  same as --core
set -euo pipefail

cd "$(dirname "$0")/.."

run_app=1
for arg in "$@"; do
    case "$arg" in
        --core | --no-app) run_app=0 ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

stage() {
    echo
    echo "==> $1"
}

# Source paths only: Packages/*/.build holds checked-out dependencies and generated files.
format_paths=(
    Packages/DescriberCore/Package.swift
    Packages/DescriberCore/Sources
    Packages/DescriberCore/Tests
    InterfaceDescriber
    InterfaceDescriberTests
)

stage "Core tests"
swift test --package-path Packages/DescriberCore

stage "Example project (Schema/examples/acme.uidesc re-saves byte for byte and matches the schema)"
swift test --package-path Packages/DescriberCore --filter ExampleProjectTests

stage "Format check"
if swift format --version > /dev/null 2>&1; then
    swift_format=(swift format)
elif command -v swift-format > /dev/null 2>&1; then
    swift_format=(swift-format)
else
    echo "swift-format not found. It ships with Swift 6 toolchains (Xcode 16) as 'swift format'." >&2
    exit 1
fi
"${swift_format[@]}" lint --strict --recursive "${format_paths[@]}"

if [[ $run_app == 0 ]]; then
    echo
    echo "Skipped app stages (--core)."
    exit 0
fi

stage "Generate Xcode project"
xcodegen generate

stage "App build and tests"
xcodebuild test \
    -project InterfaceDescriber.xcodeproj \
    -scheme InterfaceDescriber \
    -destination 'platform=macOS'

echo
echo "All checks passed."
