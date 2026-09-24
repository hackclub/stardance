import test from "node:test";
import assert from "node:assert/strict";
import BlackholeController from "../../app/javascript/controllers/blackhole_controller.js";

test("navigation restores damage immediately, but live changes still animate", () => {
  const controller = {
    scenesBlocked: () => false,
    visualIntensityValue: 100,
    cutSurfaces(emit) {
      this.emitted = emit;
    },
    wake() {},
  };
  BlackholeController.prototype.setIntensity.call(controller, 25, {
    immediate: true,
  });
  assert.equal(controller.level, 0.25);
  assert.equal(controller.emitted, false);
  BlackholeController.prototype.setIntensity.call(controller, 50);
  assert.equal(controller.level, 0.25);
  assert.equal(controller.requested, 0.5);
});

test("simulated hours and strength override live polls without replacing live state", () => {
  const controller = {
    simulatorEnabledValue: true,
    simulation: { damage: 75, strength: 50, buku: 2500, bean: 0 },
    scenesBlocked: () => false,
    dispatch(name, { detail }) {
      this.progress = detail;
    },
    wake() {},
  };
  BlackholeController.prototype.setIntensity.call(controller, 30);
  assert.equal(controller.latestIntensity, 30);
  assert.equal(controller.requested, 0.375);
  assert.deepEqual(controller.progress, {
    percent: 75,
    hours: { buku: 2500, bean: 0 },
  });
  controller.simulation = null;
  BlackholeController.prototype.setIntensity.call(
    controller,
    controller.latestIntensity,
  );
  assert.equal(controller.requested, 0.3);
});

test("simulator actions are inert when the server has not enabled the simulator", () => {
  const controller = { simulatorEnabledValue: false };
  BlackholeController.prototype.simulate.call(controller, {
    preventDefault() {},
  });
  BlackholeController.prototype.resetSimulation.call(controller);
  assert.equal(controller.simulation, undefined);
});

test("simulator can disable cursor repair", () => {
  const strength = BlackholeController.prototype.repairStrength.call(
    { simulation: { cursorRepair: false } },
    {},
    {},
  );
  assert.equal(strength, 0);
});

test("initial damage cannot bypass the intro or role reveal", () => {
  const controller = {
    scenesBlocked: () => true,
    reset() {
      this.level = this.requested = 0;
    },
    cutSurfaces() {
      assert.fail("must not disintegrate story scenes");
    },
  };
  BlackholeController.prototype.setIntensity.call(controller, 75, {
    immediate: true,
  });
  assert.equal(controller.level, 0);
});

test("sidebar fragmentation does not change with page surface count", () => {
  for (const selector of [
    "#primary-nav",
    ".sidebar__logo-img",
    ".sidebar__user-card",
  ]) {
    const element = { matches: (value) => value === selector };
    const seed = (size) =>
      BlackholeController.prototype.surfaceSeed.call(
        { surfaces: { size } },
        element,
      );
    assert.equal(seed(3), seed(25));
    assert.ok(seed(3) < 0);
  }
});

test("particle opt-out disables both ambient dust and destruction bursts", () => {
  const controller = {
    particlesEnabledValue: false,
    reducedMotion: { matches: false },
    level: 1,
    particles: [],
    fringe: [{ x: 10, y: 20 }],
    emitDust: BlackholeController.prototype.emitDust,
  };
  BlackholeController.prototype.emitAmbientDust.call(controller, 1);
  controller.emitDust(100);
  assert.equal(controller.particles.length, 0);
  assert.equal(controller.dustBudget, undefined);
});

test("restoring a simulator preview cannot overwrite the saved particle opt-out", () => {
  const fields = {
    damage: { value: "64" },
    buku: { value: "0" },
    bean: { value: "0" },
    strength: { value: "100" },
    particles: { checked: true },
    cursorRepair: { checked: true },
  };
  const controller = {
    particlesEnabledValue: false,
    simulatorFormTarget: { elements: { namedItem: (name) => fields[name] } },
    simulatorStatusTarget: {},
  };
  BlackholeController.prototype.readSimulation.call(controller);
  assert.equal(
    controller.simulation.particles,
    true,
    "even an older saved preview may request particles",
  );
  assert.equal(
    controller.particlesEnabledValue,
    false,
    "the saved preference remains authoritative",
  );
});

test("particles require both user permission and simulator permission", () => {
  for (const [preference, preview, expected] of [
    [false, true, 0],
    [true, false, 0],
    [true, true, 45],
  ]) {
    const controller = {
      particlesEnabledValue: preference,
      simulation: { particles: preview },
      reducedMotion: { matches: false },
      level: 1,
      particles: [],
      fringe: [{ x: 10, y: 20 }],
      emitDust: BlackholeController.prototype.emitDust,
    };
    BlackholeController.prototype.emitAmbientDust.call(controller, 1);
    assert.equal(controller.particles.length, expected);
    controller.particles = [];
    controller.emitDust(8);
    assert.equal(controller.particles.length, expected ? 8 : 0);
    if (!expected) {
      controller.canvasContext = {
        clearRect() {},
        save() {
          assert.fail("disabled particles must not be painted");
        },
      };
      controller.particles = [{ age: 0, life: 1 }];
      BlackholeController.prototype.draw.call(controller, 0.01);
    }
  }
});

test("ambient dust is restrained and respects reduced motion", () => {
  const controller = {
    particlesEnabledValue: true,
    reducedMotion: { matches: false },
    level: 1,
    particles: [],
    fringe: [{ x: 10, y: 20 }],
    emitDust: BlackholeController.prototype.emitDust,
  };
  BlackholeController.prototype.emitAmbientDust.call(controller, 1);
  assert.equal(controller.particles.length, 45);
  controller.emitDust(1000);
  assert.equal(controller.particles.length, 180);
  assert.ok(controller.particles.every((p) => p.size <= 4 && p.life <= 2.5));
  controller.particles = [];
  controller.reducedMotion.matches = true;
  controller.emitDust(100);
  assert.equal(controller.particles.length, 0);
});

test("cursor repair finishes even with particles disabled", () => {
  let wakes = 0;
  const controller = {
    particlesEnabledValue: false,
    reducedMotion: { matches: false },
    level: 0.25,
    requested: 0.25,
    particles: [],
    repairDirty: true,
    lastMask: 100,
    cutSurfaces() {
      this.cut = true;
    },
    emitAmbientDust() {},
    draw() {},
    wake() {
      wakes++;
    },
  };
  BlackholeController.prototype.tick.call(controller, 110);
  assert.equal(wakes, 1, "a throttled repair must schedule another frame");
  BlackholeController.prototype.tick.call(controller, 150);
  assert.equal(controller.cut, true);
  assert.equal(controller.repairDirty, false);
  assert.equal(
    wakes,
    1,
    "idle dust-free pages do not need continuous animation",
  );
});

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
