#!/usr/bin/env bash
# Times the core work behind canvas events and edits on the 500-region stress project (CorePerformanceTests), in a
# release build. Runs anywhere with a Swift toolchain, including Linux cloud sessions; the app's own timings
# (CanvasPerformanceTests) need macOS.
#
#   scripts/bench.sh            print the timings
#   scripts/bench.sh --profile  also sample the run with perf and list the hottest functions (Linux, needs perf)
set -euo pipefail

cd "$(dirname "$0")/.."

profile=0
for arg in "$@"; do
    case "$arg" in
        --profile) profile=1 ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

package=Packages/DescriberCore
# `swift test` rather than `swift build`: only it builds release tests with testable imports.
swift test --package-path "$package" -c release --filter CorePerformanceTests 2>&1 | grep -E "^Core, |error|failed"
if [[ $profile == 0 ]]; then
    exit 0
fi
bin=$(swift build --package-path "$package" -c release --show-bin-path)

# Ubuntu's /usr/bin/perf refuses to run on a kernel it wasn't built for, so use the versioned binary directly.
perf=$(ls /usr/lib/linux-tools-*/perf 2> /dev/null | tail -1 || true)
if [[ -z $perf ]]; then
    echo "perf not found. On Ubuntu: apt-get install linux-tools-generic (the cloud session hook does this)." >&2
    exit 1
fi

data=$(mktemp -d)
trap 'rm -rf "$data"' EXIT
# cpu-clock: cloud VMs don't expose hardware counters.
"$perf" record -e cpu-clock -F 4000 -g -o "$data/perf.data" -- \
    "$bin/DescriberCorePackageTests.xctest" DescriberCoreTests.CorePerformanceTests > /dev/null 2>&1
echo
echo "Hottest functions (self time):"
"$perf" report -i "$data/perf.data" --stdio --no-children -g none --percent-limit 1 2> /dev/null \
    | grep '%' | swift demangle --simplified | cut -c1-200
echo
echo "Hottest DescriberCore functions (including callees):"
"$perf" report -i "$data/perf.data" --stdio --children -g none --percent-limit 2 2> /dev/null \
    | grep '%' | swift demangle --simplified | grep DescriberCore \
    | grep -vE "CorePerformanceTests|thunk" | cut -c1-200 | head -25
