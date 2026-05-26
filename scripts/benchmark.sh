#!/usr/bin/env bash
# scripts/benchmark.sh
# ---------------------------------------------------------------------------
# Reproducible throughput benchmark: generates a synthetic routing table +
# trace, runs the engine, and reports lookups/second.
#
# No external data required — all input is generated deterministically with
# awk.  Useful for comparing performance across machines or after code changes.
#
# Usage:
#   bash scripts/benchmark.sh [N_PREFIXES [N_TRACE]]
#   make bench
#
# Defaults: 100,000 prefixes, 100,000 lookups.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN="${ROOT}/iplookup"

N_PREFIXES=${1:-100000}
N_TRACE=${2:-100000}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REGION="bench"
DATE_TAG="run"
REGION_DIR="${WORK}/${REGION}"
mkdir -p "${REGION_DIR}" "${WORK}/data"

[[ -x "$BIN" ]] || { echo "error: binary not found at $BIN — run 'make' first"; exit 1; }

echo "=== ip-lpm benchmark ==="
printf "  prefixes : %d\n" "$N_PREFIXES"
printf "  lookups  : %d\n" "$N_TRACE"
echo ""

# Generate routing table — deterministic spread across /8 /16 /24.
# Linear congruential coefficients are chosen so each octet cycles with a
# different period, distributing entries across the address space.
awk -v n="$N_PREFIXES" 'BEGIN {
    print "Network"
    for (i = 0; i < n; i++) {
        a = (i * 7  + 1) % 223 + 1
        b = (i * 11 + 3) % 256
        c = (i * 13 + 5) % 256
        plen = (i % 3 == 0) ? 24 : (i % 3 == 1) ? 16 : 8
        if      (plen ==  8) printf "%d.0.0.0/%d\n",       a,       plen
        else if (plen == 16) printf "%d.%d.0.0/%d\n",      a, b,    plen
        else                 printf "%d.%d.%d.0/%d\n",     a, b, c, plen
    }
}' > "${REGION_DIR}/prefix_${DATE_TAG}.txt"

# Generate destination trace
awk -v n="$N_TRACE" 'BEGIN {
    print "Destination"
    for (i = 0; i < n; i++) {
        a = (i * 17 +  5) % 223 + 1
        b = (i * 19 +  7) % 256
        c = (i * 23 + 11) % 256
        d = (i * 29 + 13) % 256
        printf "%d.%d.%d.%d\n", a, b, c, d
    }
}' > "${REGION_DIR}/trace_${DATE_TAG}.txt"

echo "Running engine..."
echo ""

TIMING=$(cd "$WORK" && "$BIN" "$REGION" "$DATE_TAG" 2>&1)
echo "$TIMING"

# Extract LPM lookup wall-clock seconds and compute throughput
LOOKUP_SECS=$(echo "$TIMING" | sed -n 's/.*LPM lookup.*(\([0-9.]*\) s).*/\1/p')
if [[ -n "$LOOKUP_SECS" ]]; then
    THROUGHPUT=$(awk -v n="$N_TRACE" -v s="$LOOKUP_SECS" 'BEGIN { printf "%.0f", n / s }')
    CPU_INFO=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs 2>/dev/null \
        || sysctl -n machdep.cpu.brand_string 2>/dev/null \
        || echo "unavailable")
    echo ""
    echo "--- result ---"
    printf "  throughput : %s lookups/second\n" "$THROUGHPUT"
    printf "  host       : %s %s, %s\n" "$(uname -m)" "$(uname -s)" "$CPU_INFO"
    echo "--------------"
fi
