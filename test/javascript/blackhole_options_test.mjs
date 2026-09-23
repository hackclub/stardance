import test from "node:test";
import assert from "node:assert/strict";
import BlackholeController from "../../app/javascript/controllers/blackhole_controller.js";

test("admin intensity scales visuals without changing the event score", () => {
  const controller = {
    progressUrlValue: "/progress",
    scenesBlocked: () => false,
    dispatch(name, { detail }) {
      this.progress = detail;
    },
    reset() {
      this.requested = 0;
    },
    wake() {},
  };
  for (const [strength, damage, expected] of [
    [0, 75, 0],
    [50, 75, 0.375],
    [100, 75, 0.75],
    [200, 75, 1],
  ]) {
    controller.visualIntensityValue = strength;
    BlackholeController.prototype.setIntensity.call(controller, damage);
    assert.equal(controller.requested, expected);
    assert.equal(controller.progress.percent, damage);
    assert.equal(controller.latestIntensity, damage);
  }
});

test("cursor repair removes nearby holes, including at full destruction", () => {
  const cell = {
    cx: 50,
    cy: 50,
    vertices: [
      [45, 45],
      [55, 45],
      [55, 55],
      [45, 55],
    ],
    bounds: { left: 45, right: 55, top: 45, bottom: 55 },
  };
  const outer = "M-50000,-50000H50000V50000H-50000Z";
  for (const level of [0.9, 1]) {
    const controller = {
      level,
      fragmentCells: () => [cell],
      repairStrength: () => 1,
      fringe: [],
      width: 100,
      height: 100,
    };
    const path = () =>
      BlackholeController.prototype.fragmentPath.call(
        controller,
        { width: 100, height: 100, left: 0, top: 0 },
        9,
        1,
      );
    assert.equal(
      path(),
      outer,
      "nearby fragment is intact with repair enabled",
    );
    controller.repairStrength = () => 0;
    assert.notEqual(path(), outer, "moving away restores the erosion");
  }
});
