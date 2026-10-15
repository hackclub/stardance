// Rendering-math benchmark, not a browser FPS test. Run in an isolated,
// resource-limited container; see docs/disintegration-performance.md.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { performance } from "node:perf_hooks";
import { createHash } from "node:crypto";

const [revision = "working", output, onlyScenario] = process.argv.slice(2);
const file = "app/javascript/controllers/blackhole_controller.js";
let source =
  revision === "working"
    ? readFileSync(file, "utf8")
    : execFileSync(
        "git",
        ["-c", "safe.directory=/app", "show", `${revision}:${file}`],
        { encoding: "utf8" },
      );
const sourceHash = createHash("sha256").update(source).digest("hex");
for (const name of ["@hotwired/stimulus", "d3"])
  source = source.replace(
    JSON.stringify(name),
    JSON.stringify(import.meta.resolve(name)),
  );
const Controller = (
  await import(
    `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
  )
).default;
const frames = 48;
const trials = 3;
const scenarios = [
  { name: "steady-card", width: 900, height: 600, level: 0.64 },
  { name: "cursor-card", width: 900, height: 600, level: 0.94, cursor: true },
  { name: "damage-transition", width: 900, height: 600, transition: true },
  { name: "slow-scroll", width: 900, height: 5000, level: 0.64, scroll: 10 },
  { name: "fast-scroll", width: 900, height: 5000, level: 0.94, scroll: 160 },
  { name: "phantom-scroll", width: 310, height: 480, level: 0.64, scroll: 2 },
  {
    name: "phantom-cursor",
    width: 310,
    height: 480,
    level: 0.94,
    cursor: true,
  },
  {
    name: "wide-text-scroll",
    width: 1600,
    height: 5000,
    viewportWidth: 1920,
    viewportHeight: 1080,
    level: 0.94,
    scroll: 10,
    lines: 100,
  },
];
const readCgroup = (name) => {
  try {
    return readFileSync(`/sys/fs/cgroup/${name}`, "utf8").trim();
  } catch {
    return null;
  }
};
const percentile = (values, fraction) =>
  [...values].sort((a, b) => a - b)[Math.ceil(values.length * fraction) - 1];
const results = [];
// Warm the implementation before recording; measured controllers still start
// with empty caches, so cold-build cost remains a separate measured sample.
const makeController = (scenario) =>
  Object.assign(Object.create(Controller.prototype), {
    width: scenario.viewportWidth || 1200,
    height: scenario.viewportHeight || 800,
    level: scenario.level ?? 0.64,
    fringe: [],
    pointer: null,
    repairRadius: 145,
    repairTime: 0,
    reducedMotion: { matches: false },
  });
const warm = makeController({});
for (let i = 0; i < 8; i++)
  warm.fragmentPath({ left: 0, top: 0, width: 400, height: 300 }, 9, 7, [], []);
const throttleBefore = readCgroup("cpu.stat");
for (const scenario of scenarios) {
  if (onlyScenario && !onlyScenario.split(",").includes(scenario.name))
    continue;
  const samples = [],
    cold = [],
    totals = [],
    heap = [],
    builds = [];
  let maxCells = 0,
    pathBytes = 0;
  for (let trial = 0; trial < trials; trial++) {
    global.gc?.();
    const heapBefore = process.memoryUsage().heapUsed;
    const c = makeController(scenario);
    let previousAreas,
      previousExcluded,
      previousMesh,
      meshBuilds = 0;
    const frameTimes = [];
    for (let frame = 0; frame <= frames; frame++) {
      const offset = scenario.scroll
        ? (frame * scenario.scroll) % Math.max(1, scenario.height - 100)
        : 0;
      const rect = {
        left: 0,
        top: -offset,
        width: scenario.width,
        height: scenario.height,
      };
      c.level = scenario.transition
        ? 0.25 + (frame / frames) * 0.69
        : scenario.level;
      c.pointer =
        scenario.cursor && frame < frames * 0.75
          ? { x: 20 + ((frame * 17) % scenario.width), y: 150 }
          : null;
      c.repairTime = frame * 50;
      c.fringe = [];
      // A scroll refreshes DOM measurements in the real renderer. Stationary
      // frames reuse them; newest renderer also reuses equal local rectangles.
      let areas = previousAreas;
      let excluded = previousExcluded;
      if (!areas || scenario.scroll) {
        areas = Array.from({ length: scenario.lines || 40 }, (_, i) => ({
          left: 30,
          right: scenario.width - 30,
          top: 30 + i * 13,
          bottom: 40 + i * 13,
          kind: "text",
        }));
        excluded = [];
      }
      const start = performance.now();
      if (c.reuseRects) {
        areas = c.reuseRects(previousAreas, areas);
        excluded = c.reuseRects(previousExcluded, excluded);
      }
      const path = c.fragmentPath(rect, 9, 31, areas, excluded);
      const duration = performance.now() - start;
      previousAreas = areas;
      previousExcluded = excluded;
      const mesh = c.fragmentMeshes?.get(31)?.cells;
      if (mesh !== previousMesh) meshBuilds++;
      previousMesh = mesh;
      maxCells = Math.max(maxCells, mesh?.length || 0);
      pathBytes = Math.max(pathBytes, path.length);
      if (frame === 0) cold.push(duration);
      else {
        samples.push(duration);
        frameTimes.push(duration);
      }
    }
    totals.push(frameTimes.reduce((sum, value) => sum + value, 0));
    builds.push(meshBuilds);
    global.gc?.();
    heap.push(
      Math.max(0, process.memoryUsage().heapUsed - heapBefore) / 1048576,
    );
  }
  const round = (n) => Number(n.toFixed(2));
  results.push({
    scenario: scenario.name,
    samples: samples.length,
    medianMs: round(percentile(samples, 0.5)),
    p95Ms: round(percentile(samples, 0.95)),
    maxMs: round(Math.max(...samples)),
    coldMedianMs: round(percentile(cold, 0.5)),
    trialTotalMs: totals.map(round),
    meshBuilds: builds,
    maxCells,
    maxPathBytes: pathBytes,
    // Incremental post-GC heap growth, not total cache size or a leak test.
    heapGrowthAfterGcMiB: heap.map(round),
    over16msPercent: round(
      (100 * samples.filter((n) => n > 16.67).length) / samples.length,
    ),
    over50msPercent: round(
      (100 * samples.filter((n) => n > 50).length) / samples.length,
    ),
  });
  console.log(JSON.stringify(results.at(-1)));
}
const report = {
  revision,
  sourceHash,
  node: process.version,
  frames,
  trials,
  cpuMax: readCgroup("cpu.max"),
  memoryMax: readCgroup("memory.max"),
  memoryPeak: readCgroup("memory.peak"),
  memoryEvents: readCgroup("memory.events"),
  maxRssKiB: process.resourceUsage().maxRSS,
  throttleBefore,
  throttleAfter: readCgroup("cpu.stat"),
  results,
};
if (output) writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
console.log(
  JSON.stringify({
    revision,
    cpuMax: report.cpuMax,
    maxRssKiB: report.maxRssKiB,
  }),
);
