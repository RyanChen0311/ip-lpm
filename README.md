# ip-lpm

> A high-performance IPv4 routing engine implemented in C, using a **32-level Binary Trie** to perform **Longest Prefix Match (LPM)** — the same algorithm used inside real-world routers and network ASICs.

[![CI](https://github.com/RyanChen0311/ip-lpm/actions/workflows/ci.yml/badge.svg)](https://github.com/RyanChen0311/ip-lpm/actions/workflows/ci.yml)

---

## Overview

IP routing requires finding the *most specific* matching prefix for any destination address.  This project implements that lookup from scratch in standard C, operating on real-world BGP routing table snapshots from [RIPE NCC Route Collectors](https://www.ripe.net/analyse/internet-measurements/routing-information-service-ris).

The engine can resolve **1 million+ prefixes** against large trace files and reports wall-clock timing for every phase of the pipeline.

---

## Algorithm

```
Destination:  192.168.1.1
Binary form:  11000000 10101000 00000001 00000001

             [root]
            /       \
          [0]       [1]   ← bit 0 = 1  →  go right
                   /   \
                 [0]   [1]   ← bit 1 = 1  →  go right
                 ...
          [match: 192.168.0.0/16]   ← deepest matching prefix = LPM result
```

Every bit of the destination address selects a left (0) or right (1) child.  Whenever a node carries a routing table index, it becomes the current *best match*.  The deepest such match at the end of traversal is the forwarding decision.

---

## Project Structure

```
ip-lpm/
├── src/
│   ├── main.c              # Entry point, CLI argument handling, pipeline driver
│   ├── trie.c              # Binary trie: insert / search (LPM) / free
│   ├── convert.c           # CIDR prefix & IP trace → 32-bit binary string
│   └── lookup.c            # End-to-end pipeline: table build + forwarding loop
├── include/
│   ├── ip_types.h          # Core structs: TrieNode, PrefixInfo, BinIPWithLen
│   ├── trie.h              # Trie interface
│   ├── convert.h           # Conversion interface
│   └── lookup.h            # Lookup engine interface
├── scripts/
│   ├── fetch_bgp_data.sh   # Download & convert real BGP routing table from RIPE NCC
│   └── smoke_test.sh       # Automated correctness test (no external data required)
├── data/                   # Generated output files (git-ignored)
├── docs/                   # Doxygen output
├── Makefile
└── Doxyfile
```

---

## Build

**Requirements:** GCC ≥ 9 (or any C11-compatible compiler), GNU Make

```bash
# Release build
make

# Debug build (AddressSanitizer + UBSan enabled)
make debug

# Generate Doxygen documentation
make docs

# Run smoke test (no external data needed)
make test
```

The binary is placed at `./iplookup`.

---

## Quick Start with Real BGP Data

### Step 1 — Install dependencies

```bash
sudo apt-get install -y bgpdump wget
```

### Step 2 — Download and convert a real routing table

```bash
bash scripts/fetch_bgp_data.sh rrc00 20211122
```

This script downloads the latest BGP routing table snapshot from RIPE NCC RIS (~400 MB),
extracts all unique IPv4 prefixes, and writes two files ready for the engine:

```
rrc00/prefix_20211122.txt   # ~1,100,000 CIDR prefixes
rrc00/trace_20211122.txt    # 100,000 destination IPs (one per prefix)
```

> The data files are git-ignored due to size. Re-run the script any time to refresh.

### Step 3 — Build the binary

```bash
make
```

### Step 4 — Run the lookup engine

```bash
./iplookup rrc00 20211122
```

---

## Scripts

### `scripts/fetch_bgp_data.sh`

Downloads a real BGP routing table from [RIPE NCC RIS](https://www.ripe.net/analyse/internet-measurements/routing-information-service-ris) and prepares it for the engine.

```bash
bash scripts/fetch_bgp_data.sh [region] [date_tag]
```

| Argument | Default | Description |
|----------|---------|-------------|
| `region` | `rrc00` | Route collector region (`rrc00` `rrc01` `rrc03` `rrc04` `rrc05`) |
| `date_tag` | today (`YYYYMMDD`) | Label used in output file names |

**What it does internally:**

| Step | Action |
|------|--------|
| 1 | Downloads `latest-bview.gz` from `data.ris.ripe.net/<region>/` |
| 2 | Converts MRT binary → IPv4 CIDR prefix list using `bgpdump`, deduplicates |
| 3 | Writes `<region>/prefix_<date_tag>.txt` (header + one CIDR per line) |
| 4 | Writes `<region>/trace_<date_tag>.txt` (header + up to 100,000 destination IPs) |

**Files produced:**

```
<region>/
├── latest-bview.gz          # Raw MRT download (~400 MB, can be deleted after step 2)
├── prefixes_raw.txt         # Intermediate deduplicated prefix list
├── prefix_<date_tag>.txt    # Engine input: routing table
└── trace_<date_tag>.txt     # Engine input: destination IP trace
```

---

### `scripts/smoke_test.sh`

Automated correctness test that runs without any external data.  Used by CI on every push.

```bash
bash scripts/smoke_test.sh
# or
make test
```

**What it verifies:**

| Test | What is checked |
|------|----------------|
| Argument validation | Binary exits non-zero on missing / invalid arguments |
| Pipeline execution | Full pipeline runs without crashing on synthetic data |
| Line count | Output contains exactly one line per trace entry |
| LPM correctness | Five destinations with overlapping prefixes (`/8` `/16` `/24`) each resolve to the expected next-hop |

---

## Usage

```
./iplookup <region> <date_tag>
```

| Argument | Values |
|----------|--------|
| `region` | `rrc00` `rrc01` `rrc03` `rrc04` `rrc05` `Final` |
| `date_tag` | Date string matching your input files, e.g. `20211122` |

**Expected input layout:**

```
./<region>/prefix_<date_tag>.txt    # CIDR prefix list
./<region>/trace_<date_tag>.txt     # Destination IP trace
```

**Prefix file format** (first line is a skipped header):
```
Network
192.168.0.0/16
10.0.0.0/8
0.0.0.0/0
```

**Trace file format** (first line is a skipped header):
```
Destination
192.168.1.1
10.5.5.5
8.8.8.8
```

---

## Output Files

All output is written to `./data/` (git-ignored):

```
data/
├── prefix_bin_<region>_<date_tag>.txt   # Routing table in 32-bit binary string form
├── trace_bin_<region>_<date_tag>.txt    # Trace IPs in 32-bit binary string form
└── nexthop_<region>_<date_tag>.txt      # Final result: one next-hop per destination
```

### Reading the result

`data/nexthop_<region>_<date_tag>.txt` contains one line per trace entry.
Each line is the CIDR prefix of the longest-matching route:

```
1.0.0.0/24
1.0.4.0/22
10.0.0.0/8
192.168.0.0/16
0.0.0.0/0
```

- A specific prefix (e.g. `192.168.0.0/16`) means the destination matched that route.
- `0.0.0.0/0` means no specific prefix matched — the engine fell back to the default route.

### Interpreting the timing output

```
[timing] alloc nexthop table              3557 ticks  (0.0036 s)
[timing] load nexthop table             108319 ticks  (0.1083 s)
[timing] parse routing table            206221 ticks  (0.2062 s)
[timing] build binary trie              116122 ticks  (0.1161 s)
[timing] LPM lookup (all trace)          22757 ticks  (0.0228 s)
[lookup] total lookups: 100000  |  default-route fallbacks: 1
```

| Field | Meaning |
|-------|---------|
| `alloc nexthop table` | Time to allocate memory for the next-hop string table |
| `load nexthop table` | Time to read next-hop addresses from the prefix file |
| `parse routing table` | Time to read and parse the binary prefix file |
| `build binary trie` | Time to insert all prefixes into the trie |
| `LPM lookup (all trace)` | Time to resolve all trace destinations — the core benchmark |
| `default-route fallbacks` | Destinations with no matching prefix; fell back to `0.0.0.0/0` |

With a real BGP table (~1.1M prefixes, 100K lookups), representative results on a modern x86-64 Linux machine (Intel Core i7, 16 GB RAM):

| Metric | Value |
|--------|-------|
| Prefixes loaded | ~1,100,000 |
| LPM lookup time | ~0.023 s for 100,000 queries |
| Throughput | ~4,300,000 lookups / second |
| Default-route fallbacks | < 5 (near-complete internet coverage) |

To reproduce these numbers on your own machine without downloading BGP data, run:

```bash
make bench
```

`scripts/benchmark.sh` generates 100,000 synthetic prefixes and 100,000 trace IPs locally, then reports measured throughput.

---

## CI / Continuous Integration

Every push and pull request automatically triggers a build-and-test pipeline via **GitHub Actions** (`.github/workflows/ci.yml`).

### What runs on each push

```
git push
    │
    ▼
GitHub Actions spins up a fresh Ubuntu VM
    │
    ├── make                  # compile all source files
    └── make test             # run scripts/smoke_test.sh
            │
            ├── [PASS] argument validation
            ├── [PASS] pipeline produces correct line count
            └── [PASS] LPM correctness (longest prefix wins at every level)
```

### Workflow file

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: make
      - run: make test
```

The green badge at the top of this README reflects the latest pipeline result.
A red badge means the most recent push failed to compile or failed a test.

---

## Performance Notes

| Phase | Bottleneck | Notes |
|-------|-----------|-------|
| Prefix conversion | File I/O + `strtok` parsing | Linear in number of prefixes |
| Trie construction | Pointer chasing + `malloc` | ~1M insertions, up to 32 levels deep |
| LPM lookup | Cache miss on trie traversal | O(32) worst case per lookup |
| Memory | ~33 MB for 1M next-hop strings | Tunable via `MAX_NEXTHOPS` |

---

## Known Limitations

- IPv4 only (32-bit addresses).
- Single-threaded; the lookup loop is embarrassingly parallel and could use `pthreads`.
- Fixed `MAX_NEXTHOPS` (1M) and `MAX_PREFIXES` (1M); adjust in `include/ip_types.h` for larger tables.

---

## Background

Motivated by the observation that hardware routers (Cisco, Juniper) implement binary-trie structures in silicon, this project builds the same algorithm in software — implementing full Longest Prefix Match from scratch in C and validating the results against a real BGP snapshot of 1,127,835 prefixes from RIPE NCC RIS.

The design prioritises transparent performance measurement: each pipeline stage is timed independently, making bottlenecks immediately visible without a profiler.

---

## License

MIT — see [LICENSE](LICENSE).
