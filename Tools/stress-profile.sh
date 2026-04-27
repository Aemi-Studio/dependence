#!/usr/bin/env bash
#
# Tools/stress-profile.sh
#
# Drives the ExampleStressApp executable through a small set of headless
# benchmarks and prints a single, easy-to-diff report.
#
# What it covers
# --------------
#   1. Cold start  — N back-to-back launches; we capture wall-time, peak
#                    resident set, and page-fault counts via `time -l`.
#                    Establishes a baseline for the "first read of every
#                    DependencyKey" path through `DependencyValues.resolve`.
#
#   2. Resolution  — `--bench resolve` reads all 20 registered keys per
#                    iteration. With caching warmed up this is dominated by
#                    `withLock` + dictionary lookup; the printed `ns/op`
#                    measures one *resolution*, not one iteration of 20.
#
#   3. Overrides   — `--bench nested` enters two nested `withDependencies`
#                    blocks per iteration. Exercises TaskLocal push/pop and
#                    per-instance override storage.
#
#   4. Graph walk  — `--bench graph` invokes the StressViewModel.refresh()
#                    pipeline, which fans through ~10 services into the HTTP
#                    clients. The most realistic single-frame load.
#
#   5. Heap snapshot (macOS only) — `heap` against a long-lived `--bench all`
#                    process so allocator accounting can confirm the resolver
#                    cache is not unboundedly retaining values per resolve.
#
# Usage
# -----
#   Tools/stress-profile.sh                 # release config, default knobs
#   Tools/stress-profile.sh debug           # -c debug instead of release
#   ITERATIONS=200000 Tools/stress-profile.sh
#   COLD_RUNS=15 Tools/stress-profile.sh
#
# Output is machine-grep-friendly: each measurement line starts with `[name]`
# so a watchdog (or the human reading it) can `grep '\[resolve' output.txt`
# and pull out one number.

set -euo pipefail

CONFIG="${1:-release}"
ITERATIONS="${ITERATIONS:-100000}"
NESTED_ITERATIONS="${NESTED_ITERATIONS:-50000}"
GRAPH_ITERATIONS="${GRAPH_ITERATIONS:-2000}"
COLD_RUNS="${COLD_RUNS:-10}"

cd "$(dirname "$0")/.."

echo "==> Building ExampleStressApp [-c $CONFIG]"
swift build -c "$CONFIG" --product ExampleStressApp >/dev/null

BIN="$(swift build -c "$CONFIG" --show-bin-path)/ExampleStressApp"
if [ ! -x "$BIN" ]; then
    echo "build did not produce $BIN" >&2
    exit 1
fi

echo "==> Binary: $BIN"
ls -lh "$BIN" | awk '{ printf "[binary] size=%s\n", $5 }'

# 1. Cold start ---------------------------------------------------------------
echo "==> Cold start ($COLD_RUNS runs)"
for i in $(seq 1 "$COLD_RUNS"); do
    # `/usr/bin/time -l` gives us wall-clock + max RSS + page faults on macOS.
    /usr/bin/time -l "$BIN" --bench cold-start 2>&1 \
        | awk -v i="$i" '
            /^\[cold-start\]/ { line=$0 }
            /real/            { real=$1 }
            /maximum resident set size/ { rss=$1 }
            /page reclaims/   { reclaims=$1 }
            END {
                printf "[cold-start.run] i=%d %s real=%ss rss=%sB reclaims=%s\n", i, line, real, rss, reclaims
            }'
done

# 2. Resolution ---------------------------------------------------------------
echo "==> Resolution bench (iterations=$ITERATIONS)"
"$BIN" --bench resolve --iterations "$ITERATIONS"

# 3. Nested overrides ---------------------------------------------------------
echo "==> Nested override bench (iterations=$NESTED_ITERATIONS)"
"$BIN" --bench nested --iterations "$NESTED_ITERATIONS"

# 4. Graph walk ---------------------------------------------------------------
echo "==> Graph walk bench (iterations=$GRAPH_ITERATIONS)"
"$BIN" --bench graph --iterations "$GRAPH_ITERATIONS"

# 5. Heap snapshot (best-effort) ----------------------------------------------
if command -v heap >/dev/null 2>&1; then
    echo "==> Heap snapshot during long-running --bench all"
    "$BIN" --bench all --iterations "$ITERATIONS" &
    BENCH_PID=$!
    # Give the process a moment to wire up the registry and start churning.
    sleep 0.3
    if kill -0 "$BENCH_PID" 2>/dev/null; then
        heap "$BENCH_PID" 2>/dev/null \
            | awk '/Process [0-9]+:/ || /All zones/ || /^Total/ { print "[heap] " $0 }' \
            | head -10 || true
    fi
    wait "$BENCH_PID" || true
else
    echo "[heap] skipped — \`heap\` not on PATH (this is macOS-only)"
fi

echo "==> Done"
