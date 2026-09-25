import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import BlackholeController from "../../app/javascript/controllers/blackhole_controller.js";

const rect = { left: 0, top: 0, width: 900, height: 600 };
const areas = Array.from({ length: 40 }, (_, i) => ({
  left: 30,
  right: 650,
  top: 30 + i * 13,
  bottom: 40 + i * 13,
  kind: "text",
}));

function controller() {
  return Object.assign(Object.create(BlackholeController.prototype), {
    width: 1200,
    height: 800,
    level: 0.64,
    fringe: [],
    pointer: null,
    repairRadius: 145,
    repairTime: 0,
    reducedMotion: { matches: false },
  });
}

test("cached masks exactly preserve the previous staged decay pattern", () => {
  const c = controller();
  const excluded = [];
  // Captured from the pre-optimization implementation at three decay stages.
  for (const [level, hash] of [
    [0.25, "0178e138849a80bf5691bdea97c257ddb98cd6b8fb27fc7756ef74cf94cd0a81"],
    [0.64, "f3e47170fce97f8ee9e5395e7da2332ce051dcb81d7651e48d7382f47f91d61e"],
    [0.9, "aa8837cc32cde70850d56d33c79423aa65694649a847f4dff494f65eb318a9d2"],
  ]) {
    c.level = level;
    const path = c.fragmentPath(rect, 9, 31, areas, excluded);
    assert.equal(createHash("sha256").update(path).digest("hex"), hash);
    const field = c.fragmentFields.get(31).field;
    assert.equal(c.fragmentPath(rect, 9, 31, areas, excluded), path);
    assert.equal(c.fragmentFields.get(31).field, field);
  }
});

test("fragment fields invalidate when geometry, protected content, or exclusions change", () => {
  const c = controller();
  const excluded = [];
  const field = c.fragmentField(rect, 9, 31, areas, excluded);
  assert.notEqual(
    c.fragmentField({ ...rect, width: 800 }, 9, 31, areas, excluded),
    field,
  );
  const resized = c.fragmentFields.get(31).field;
  assert.notEqual(
    c.fragmentField({ ...rect, width: 800 }, 9, 31, [...areas], excluded),
    resized,
  );
  const allExcluded = [{ left: -100, top: -100, right: 1000, bottom: 700 }];
  assert.deepEqual(c.fragmentField(rect, 9, 31, areas, allExcluded), []);
});

test("cursor repairs and subsequent decay remain live on cached fields", () => {
  const c = controller();
  c.level = 0.9;
  const excluded = [];
  const damaged = c.fragmentPath(rect, 9, 31, areas, excluded);
  const field = c.fragmentFields.get(31).field;
  c.pointer = { x: 300, y: 200 };
  c.repairTime = 50;
  assert.notEqual(c.fragmentPath(rect, 9, 31, areas, excluded), damaged);
  assert.equal(c.fragmentFields.get(31).field, field);
  c.pointer = null;
  c.repairTime = 10000;
  assert.equal(c.fragmentPath(rect, 9, 31, areas, excluded), damaged);
});

test("cursor-only changes reuse text measurements but scrolling and mutations invalidate them", () => {
  const previousStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = () => ({ zIndex: "5" });
  try {
    const c = controller();
    let reads = 0;
    c.textRevision = 1;
    c.protectedRects = () => {
      reads++;
      return [];
    };
    const element = {};
    const surface = { card: true, seed: 1 };
    const initial = c.surfaceGeometry(element, surface, rect);
    assert.equal(c.surfaceGeometry(element, surface, { ...rect }), initial);
    assert.equal(reads, 1);
    c.surfaceGeometry(element, surface, { ...rect, top: -20 });
    assert.equal(reads, 2);
    c.dirty = true;
    c.surfaceGeometry(element, surface, { ...rect, top: -20 });
    assert.equal(reads, 3);
    c.dirty = false;
    c.textRevision++;
    c.surfaceGeometry(element, surface, { ...rect, top: -20 });
    assert.equal(reads, 4);
  } finally {
    if (previousStyle) globalThis.getComputedStyle = previousStyle;
    else delete globalThis.getComputedStyle;
  }
});

test("slow masks lower their update rate and recover when work becomes cheaper", () => {
  const c = controller();
  c.recordMaskCost(100);
  assert.equal(c.maskInterval, 160);
  for (let i = 0; i < 30; i++) c.recordMaskCost(1);
  assert.equal(c.maskInterval, 45);
});

test("throttled dirty masks keep scheduling until the final state is painted", () => {
  let cuts = 0;
  let wakes = 0;
  const c = {
    level: 0.25,
    requested: 0.25,
    lastTime: 100,
    lastMask: 100,
    maskInterval: 100,
    dirty: true,
    particles: [],
    reducedMotion: { matches: false },
    cutSurfaces() {
      cuts++;
    },
    emitAmbientDust() {},
    draw() {},
    wake() {
      wakes++;
    },
  };
  BlackholeController.prototype.tick.call(c, 110);
  assert.equal(cuts, 0);
  assert.equal(wakes, 1);
  BlackholeController.prototype.tick.call(c, 140);
  assert.equal(cuts, 0);
  assert.equal(wakes, 2);
  BlackholeController.prototype.tick.call(c, 210);
  assert.equal(cuts, 1);
  assert.equal(c.dirty, false);
  assert.equal(wakes, 2);
});

test("reduced motion paints dirty masks immediately without needing another animation frame", () => {
  let cuts = 0;
  const c = {
    level: 0.25,
    requested: 0.25,
    lastMask: 100,
    lastTime: 100,
    maskInterval: 160,
    dirty: true,
    particles: [],
    reducedMotion: { matches: true },
    cutSurfaces() {
      cuts++;
    },
    emitAmbientDust() {},
    draw() {},
    wake() {},
  };
  BlackholeController.prototype.tick.call(c, 110);
  assert.equal(cuts, 1);
});
