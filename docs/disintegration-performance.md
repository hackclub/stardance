# Disintegration performance comparison — September 26, 2026

## Scope and method

Compared the actual `fragmentPath` implementation in three revisions:

- **Main:** `3045af69de136b00e89daf1ef5ac8193add87c06`.
- **Previous performance version:** `535cb819927a9265ed386333e9c86a892afd8795`.
- **New:** working-tree renderer with local-rectangle reuse and a 128px mesh overscan margin (source SHA-256 `19b14ba7a8f91ba24e781db99153bf222cb8348d886014c59d6d9b60b574a29c`).

Node 22 in isolated OrbStack Docker containers. Revisions run sequentially,
in a fresh process, using these CPU/RAM limits: 1 CPU/512 MiB,
0.5 CPU/256 MiB, and 0.25 CPU/192 MiB. Swap is capped at the memory limit.
The running Rails server and user's browser resource limits are unchanged.

Each scenario has three trials of 48 measured updates, plus one separately
measured cold build per trial. There is a small implementation warm-up before
testing. Caches start empty for every trial. The harness uses real controller
methods, deterministic geometry, and simulated text measurements. It does not
replace the renderer with a simplified implementation.

Scenarios: stationary card, moving cursor followed by repair decay, 25–94%
damage transition, slow and fast tall-surface scrolling, scrolling and cursor
repair on a Phantom-sized card, and a 1920×1080 text-heavy viewport. Slow scroll
moves 10px per update; fast scroll moves 160px. Tall surfaces are 5000px high.
The Phantom-sized surface is 310×480px. Most scenarios contain 40 text rectangles;
the wide viewport contains 100. Grid size is 9px throughout.

**These are rendering-math timings, not browser FPS measurements.** They exclude
DOM measurement, SVG parsing/painting, layout, compositing, particle canvas draws,
and the Phantom WebGL shader. Fractional Docker CPU quotas cause scheduling
pauses; they do not emulate a specific low-end processor or GPU. A 16.7ms
calculation already consumes an entire 60Hz frame budget before those other
costs, but a faster calculation alone cannot establish a smooth frame rate.

`trialTotalMs / 48` includes rebuilds in the average update cost. Median timings
alone hide the expensive cache-boundary updates. Cold costs are reported
separately. Run order is fixed, not randomized; three trials are useful for
diagnosis, not a statistically controlled hardware certification.

## Reproduce

From the repository root, choose an unused service port and an existing absolute
output directory. For example:

```sh
BENCH_RESULTS_DIR=/absolute/path/to/results \
BENCH_CPUS=0.25 BENCH_MEMORY=192m STARDANCE_PORT=3003 \
docker compose -f docker-compose.yml \
  -f script/benchmark_disintegration.compose.yml \
  run --rm --no-deps --service-ports --entrypoint node web \
  --expose-gc script/benchmark_disintegration.mjs working \
  /benchmark-results/quartercpu-working.json
```

Replace `working` with either commit above to compare a baseline. Repeat with
the other CPU/RAM profiles. An optional third argument selects comma-separated
scenario names (for example `steady-card,slow-scroll,fast-scroll,phantom-scroll`).
The JSON includes controller source hashes, timing
distributions, mesh-build counts, process peak RSS, cgroup peak memory, and actual
CPU throttle and OOM counters. No database writes, feature-flag changes, source
checkout changes, or production connections are involved.

## Findings

### One CPU / 512 MiB

Milliseconds per update, using the median of the three trial averages. Unlike
the per-update median, this includes the cost of mesh rebuilds during scrolling.

| Scenario                    |   Main | Previous performance |   New |
| --------------------------- | -----: | -------------------: | ----: |
| Stationary card             |   7.47 |                 0.42 |  0.29 |
| Cursor repair, 94% damage   |  15.73 |                 4.71 |  4.63 |
| Damage transition           |   8.20 |                 1.92 |  1.98 |
| Slow tall-surface scroll    |  56.01 |                62.74 |  8.33 |
| Fast tall-surface scroll    |  61.66 |                68.30 | 89.99 |
| Phantom-sized card scroll   |   4.44 |                 4.49 |  0.08 |
| Phantom-sized cursor repair |   5.45 |                 2.50 |  2.19 |
| Wide text-heavy scroll      | 170.96 |               177.64 | 24.96 |

The slow-scroll improvement is about **6.7×**, including rebuild costs; the wide
case improves about **6.8×**. Mesh construction drops from 49 to 4 builds per
trial. The Phantom-sized scrolling card drops from 11 builds to 1.

**Fast scrolling regresses about 46% versus main.** A 160px movement usually
outruns the 128px overscan margin, rebuilding a larger mesh on 45 of 49 updates.
For the tall surface, the largest mesh grows from 9,476 to 12,463 cells. The new
cache is effective for small movements but pays extra work when it misses.

**Tail latency remains a problem.** Slow-scroll p95 rises from 86ms to 104ms,
despite the much lower average. Wide-scroll p95 rises from 203ms to 234ms. New
wide-scroll cold builds have a 282ms median. These long main-thread operations
can still cause visible stalls on slower machines.

The largest generated SVG path in the wide case grows from approximately 1.74MB
to 2.12MB. Browser parsing/painting of those paths is an additional cost absent
from this benchmark. Lower JavaScript average cost does not establish that the
full rendering pipeline is cheap.

### Half CPU / 256 MiB: incomplete comparison

Main and the previous performance version completed all scenarios. The new
renderer completed four scenarios before the runtime stalled. Docker status
queries and the local app health endpoint also stopped responding. The
benchmark container was stopped; the local app and Docker then responded, with
the health endpoint returning HTTP 200. The app and database containers were
not restarted or reconfigured.

The previous version's wide-scroll run contains a 38.8-second outlier. Its raw
result is retained, but this profile should **not** be used as a clean comparative
result. The cause of the runtime-wide stall is not established.

### Quarter CPU / 192 MiB

After the stalled run, the final profile was narrowed to four key scenarios
on main and the new renderer. Both completed. Same units and aggregation as
the one-CPU table:

| Scenario                  |   Main |    New |
| ------------------------- | -----: | -----: |
| Stationary card           |  50.00 |   2.19 |
| Slow tall-surface scroll  | 389.29 |  57.91 |
| Fast tall-surface scroll  | 408.67 | 697.73 |
| Phantom-sized card scroll |  21.05 |   2.04 |

Slow scrolling again improves **6.7×**, while fast scrolling regresses **71%**.
Slow-scroll p95 is 611ms on main and 694ms on new; fast-scroll p95 is 694ms
versus 1,092ms. The new fast-scroll cold-build median is 1,216ms. This is not
a smooth low-end experience even though cached updates themselves are cheap.

### Memory and verification

Seven complete runs produced 48 scenario results and 6,912 measured updates,
plus 144 cold-build samples. This excludes the stopped partial run. CPU quota
and throttle counters in the JSON confirm that the limits were applied.

Completed runs used roughly 103–138 MiB peak process RSS. All completed runs
reported zero cgroup OOM/OOM-kill events, including the 192 MiB profile. This is
one synthetic surface at a time, not the entire browser's footprint and not
proof of long-session memory stability. The raw `retainedHeapMiB` field is only
incremental post-GC heap growth; it is not a reliable standalone cache-size
measurement. The harness now names that field `heapGrowthAfterGcMiB` explicitly.

All **44 frontend regression tests passed**, including new diagonal scroll
reversal/geometry checks and disconnected-surface cache cleanup. Existing tests
cover deterministic visual output, scroll/text coordinates, cursor repair,
reduced motion, particle opt-out, and Phantom render scheduling and quality.

In the actual local browser, the populated home feed was checked at 94% damage,
including page and nested discover-rail scrolling. Sampled text-copy coordinates
matched their original elements (0px delta), the Phantom mask was active, and
there were no browser console errors. Notifications navigation also worked.
These are correctness/sanity observations, not high-speed scroll recordings or
quantitative browser/GPU performance tests.

### Interpretation and next steps

Keep the cached geometry/field/path work: stationary interaction and small
scroll updates benefit substantially. Do not call the low-spec work finished.
The next target should be mesh rebuilding and SVG path size, especially during
large scroll jumps and first paint. Options to test include motion-aware
overscan, coarser geometry under sustained load, and moving mesh construction
off the main thread. Preserve immediate cursor and scroll alignment; reintroducing
an input/render FPS cap would not address the expensive rebuild itself.

The Phantom measurements above concern its **disintegration mask**, not shader
GPU execution. Its existing tests verify per-frame rendering, cached layout,
reused uniform arrays, adaptive resolution, and offscreen/hidden suspension.
No real GPU timing or throttled-browser FPS measurement was available here.
