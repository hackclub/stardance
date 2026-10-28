import test from "node:test";
import assert from "node:assert/strict";
import BlackholeController from "../../app/javascript/controllers/blackhole_controller.js";

function finaleController(overrides = {}) {
  return {
    finale: { from: 0.25, progress: -1, startedAt: 1000 },
    requested: 0.25,
    level: 0.25,
    reducedMotion: { matches: false },
    scenesBlocked: () => false,
    element: { style: { setProperty() {} } },
    wake() {},
    ...overrides,
  };
}

test("finale ramps over twenty seconds from the viewer's starting damage", () => {
  const controller = finaleController();
  const update = (offset) =>
    BlackholeController.prototype.updateFinale.call(controller, 1000 + offset);
  update(0);
  assert.equal(controller.requested, 0.25);
  update(10_000);
  assert.equal(controller.requested, 0.625);
  update(20_000);
  assert.equal(controller.requested, 1);
  assert.equal(controller.level, 1);
});

test("disintegration waits for the cutscene to start", () => {
  const controller = finaleController({ finale: null });
  BlackholeController.prototype.updateFinale.call(controller, Date.now());
  assert.equal(controller.requested, 0.25);
});

test("the finale overrides every preference combination, then resets to the saved settings", () => {
  for (const effects of [false, true]) {
    for (const particles of [false, true]) {
      const controller = finaleController({
        startFinale: BlackholeController.prototype.startFinale,
        updateFinale: BlackholeController.prototype.updateFinale,
        resetFinale: BlackholeController.prototype.resetFinale,
        setIntensity: BlackholeController.prototype.setIntensity,
        finale: null,
        disintegrationEnabledValue: effects,
        particlesEnabledValue: particles,
        visualIntensityValue: 100,
        latestIntensity: 25,
        progressUrlValue: "/progress",
        reset() {
          this.level = this.requested = 0;
        },
        cutSurfaces() {},
        dispatch(name, { detail }) {
          assert.equal(name, "progress", "must not skip to the video");
          this.reported = detail.percent;
        },
      });
      controller.startFinale();
      const start = controller.finale.startedAt;
      assert.equal(controller.finale.from, effects ? 0.25 : 0);
      controller.updateFinale(start + 10_000);
      const halfway = effects ? 0.625 : 0.5;
      assert.equal(controller.requested, halfway);
      controller.setIntensity(10);
      assert.equal(
        controller.requested,
        halfway,
        "polls cannot undo the finale",
      );
      assert.equal(controller.reported, 10, "team score stays real");
      controller.updateFinale(start + 20_000);
      assert.equal(controller.level, 1);

      controller.resetFinale();
      assert.equal(controller.finale, null);
      assert.equal(controller.level, effects ? 0.1 : 0);
      assert.equal(controller.disintegrationEnabledValue, effects);
      assert.equal(controller.particlesEnabledValue, particles);
    }
  }
});

test("the admin intensity kill switch still skips destruction and reaches the video", () => {
  const controller = finaleController({
    visualIntensityValue: 0,
    resetFinale() {},
    dispatch(name) {
      this.event = name;
    },
  });
  BlackholeController.prototype.startFinale.call(controller);
  assert.equal(controller.event, "finale-complete");
});

test("reduced motion reaches the final mask without animating", () => {
  const controller = finaleController({ reducedMotion: { matches: true } });
  BlackholeController.prototype.updateFinale.call(controller, 1000);
  assert.equal(controller.level, 1);
});

test("live polls keep finale damage without changing the reported team score", () => {
  const controller = finaleController({
    finale: { from: 0.25, progress: 0.5 },
    progressUrlValue: "/progress",
    dispatch(name, { detail }) {
      this.progress = detail;
    },
  });
  BlackholeController.prototype.setIntensity.call(controller, 10);
  assert.equal(controller.requested, 0.625);
  assert.equal(controller.progress.percent, 10);
  assert.equal(
    BlackholeController.prototype.repairStrength.call(controller, {}, {}),
    0,
  );
});

test("completed finale hides offscreen surfaces and text copies and makes controls inert", () => {
  const element = {
    getBoundingClientRect() {
      assert.fail("completion must cover offscreen surfaces too");
    },
    inert: false,
  };
  let mask;
  const surface = {
    path: {
      setAttribute(name, value) {
        mask = value;
      },
    },
    textCopy: { hidden: false },
  };
  const controller = {
    finale: { progress: 1 },
    level: 1,
    surfaces: new Map([[element, surface]]),
    textTarget: { hidden: false },
    recordMaskCost() {},
  };
  BlackholeController.prototype.cutSurfaces.call(controller, false);
  assert.equal(mask, "M0,0Z");
  assert.equal(element.inert, true);
  assert.equal(surface.textCopy.hidden, true);
  assert.equal(controller.textTarget.hidden, true);
});

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

test("finale dust overrides particle opt-outs, paints and settles before handing off", () => {
  let painted = 0;
  const controller = {
    finale: { progress: 0.5 },
    particlesEnabledValue: false,
    simulation: { particles: false },
    reducedMotion: { matches: false },
    level: 0.5,
    requested: 0.5,
    particles: [],
    fringe: [{ x: 10, y: 20 }],
    emitDust: BlackholeController.prototype.emitDust,
    emitAmbientDust: BlackholeController.prototype.emitAmbientDust,
    draw: BlackholeController.prototype.draw,
    canvasContext: {
      clearRect() {},
      save() {},
      translate() {},
      rotate() {},
      fillRect() {
        painted++;
      },
      restore() {},
    },
    dispatch(name) {
      this.event = name;
    },
    wake() {
      this.woke = true;
    },
  };
  controller.emitAmbientDust(1);
  controller.emitDust(8);
  assert.equal(controller.particles.length, 30);
  controller.draw(0.05);
  assert.equal(painted, 30);

  controller.finale.progress = 1;
  controller.level = controller.requested = 1;
  controller.emitAmbientDust(1);
  assert.equal(
    controller.particles.length,
    30,
    "completed destruction stops new ambient dust",
  );
  for (let frame = 0; frame < 60; frame++) controller.draw(0.05);
  assert.equal(controller.particles.length, 0);
  BlackholeController.prototype.tick.call(controller, 1000);
  assert.equal(controller.event, "finale-complete");
  assert.equal(controller.woke, undefined);

  controller.finale = null;
  controller.emitAmbientDust(1);
  controller.emitDust(8);
  assert.equal(
    controller.particles.length,
    0,
    "normal rendering honors the opt-out again",
  );
  assert.equal(controller.particlesEnabledValue, false);
  assert.equal(controller.simulation.particles, false);
});

test("the finale keeps scheduling dust frames with particles turned off in settings", () => {
  const controller = finaleController({
    finale: { progress: 0.5 },
    particlesEnabledValue: false,
    simulation: { particles: false },
    particles: [],
    emitAmbientDust() {},
    draw() {},
    wake() {
      this.woke = true;
    },
  });
  BlackholeController.prototype.tick.call(controller, 1000);
  assert.equal(controller.woke, true);
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

test("disintegration opt-out removes all damage but still reports the event score", () => {
  const controller = {
    disintegrationEnabledValue: false,
    progressUrlValue: "/progress",
    visualIntensityValue: 100,
    scenesBlocked: () => false,
    dispatch(name, { detail }) {
      this.progress = detail;
    },
    reset() {
      this.wasReset = true;
    },
    cutSurfaces() {
      assert.fail("must not fragment surfaces after opting out");
    },
  };
  BlackholeController.prototype.setIntensity.call(controller, 75, {
    immediate: true,
  });
  assert.equal(controller.requested, 0);
  assert.equal(controller.wasReset, true);
  assert.equal(controller.progress.percent, 75);
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
      fragmentField: BlackholeController.prototype.fragmentField,
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
