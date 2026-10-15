import test from "node:test";
import assert from "node:assert/strict";
import BlackholeController from "../../app/javascript/controllers/blackhole_controller.js";

const rect = { left: 0, top: 0, width: 240, height: 100 };
const image = [{ left: 0, top: 0, right: 240, bottom: 100, kind: "image" }];
const excluded = [];
const intact = "M-50000,-50000H50000V50000H-50000Z";

function controller() {
  return Object.assign(Object.create(BlackholeController.prototype), {
    width: 1200,
    height: 800,
    level: 0.25,
    fringe: [],
    pointer: null,
    repairRadius: 145,
    repairTime: 0,
    reducedMotion: { matches: false },
  });
}

function mask(c, proportional = true) {
  return c.fragmentPath(rect, 9, -62, image, excluded, true, proportional);
}

test("logo damage starts immediately, tracks the damage range, and is reversible", () => {
  const c = controller();
  const snapshots = new Map();
  for (const level of [0, 0.25, 0.5, 0.75, 1]) {
    c.level = level;
    snapshots.set(level, mask(c));
    const entries = c.fragmentFields
      .get(-62)
      .field.filter(
        ({ cell }) =>
          cell.cx >= 0 &&
          cell.cx <= rect.width &&
          cell.cy >= 0 &&
          cell.cy <= rect.height,
      );
    const damage =
      entries.reduce((sum, { erosion = 0 }) => sum + erosion ** 2, 0) /
      entries.length;
    assert.ok(
      Math.abs(damage - level) < 0.07,
      `${level}: actual damage ${damage}`,
    );
  }
  assert.equal(snapshots.get(0), intact);
  assert.notEqual(snapshots.get(0.25), intact);
  for (const level of [0.75, 0.5, 0.25, 0]) {
    c.level = level;
    assert.equal(mask(c), snapshots.get(level));
  }
});

test("proportional logo fields are cached separately from staged image decay", () => {
  const c = controller();
  const stagedPath = mask(c, false);
  const staged = c.fragmentFields.get(-62).field;
  assert.ok(
    staged
      .filter(
        ({ cell }) =>
          cell.cx >= 0 &&
          cell.cx <= rect.width &&
          cell.cy >= 0 &&
          cell.cy <= rect.height,
      )
      .every(({ start }) => start >= 0.6),
    "ordinary images still survive early damage",
  );
  const path = mask(c);
  const proportional = c.fragmentFields.get(-62).field;
  assert.notEqual(proportional, staged);
  assert.notEqual(path, intact);
  assert.equal(mask(c), path);
  assert.equal(c.fragmentFields.get(-62).field, proportional);
  assert.equal(mask(c, false), stagedPath);
});

test("logo fragments use the shared cursor repair and decay back after it leaves", () => {
  const c = controller();
  c.level = 1;
  const damaged = mask(c);
  c.pointer = { x: 120, y: 50 };
  const repaired = mask(c);
  assert.notEqual(repaired, damaged);
  const center = c.fragmentFields
    .get(-62)
    .field.find(({ cell }) => Math.hypot(cell.cx - 120, cell.cy - 50) < 15);
  assert.equal(center.cell.repair, 1);
  c.pointer = null;
  c.repairTime = 100;
  mask(c);
  assert.ok(center.cell.repair > 0 && center.cell.repair < 1);
  c.repairTime = 10000;
  assert.equal(mask(c), damaged);
});
