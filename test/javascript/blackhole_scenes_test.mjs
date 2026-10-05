import test from "node:test";
import assert from "node:assert/strict";
import BlackholeController from "../../app/javascript/controllers/blackhole_controller.js";

test("the Crescent ad receives its own card mask without masking its canvas separately", () => {
  const originalDocument = globalThis.document;
  const style = new Map();
  const ad = {
    id: "",
    isConnected: true,
    parentElement: { closest: () => null },
    closest: () => null,
    matches: (selector) => selector.split(", ").includes(".crescent-promo"),
    getBoundingClientRect: () => ({ width: 310, height: 480 }),
    style: {
      getPropertyValue: (name) => style.get(name) || "",
      getPropertyPriority: () => "",
      setProperty: (name, value) => style.set(name, value),
    },
  };
  const canvas = {
    matches: (selector) => selector.split(", ").includes("canvas"),
  };
  let masks = 0;
  let observed = 0;
  try {
    globalThis.document = {
      body: { children: [] },
      querySelectorAll: (selector) =>
        [ad, canvas].filter((element) => element.matches(selector)),
      createElementNS: () => ({ setAttribute() {}, append() {} }),
    };
    const controller = {
      surfaces: new Map(),
      surfaceSeed: BlackholeController.prototype.surfaceSeed,
      element: { contains: () => false },
      masksTarget: { firstElementChild: { append: () => masks++ } },
      surfaceResize: { observe: () => observed++ },
    };
    BlackholeController.prototype.collectSurfaces.call(controller);
    BlackholeController.prototype.collectSurfaces.call(controller);
    assert.equal(controller.surfaces.size, 1);
    assert.equal(controller.surfaces.get(ad).card, true);
    assert.match(style.get("clip-path"), /^url\(#blackhole-cut-/);
    assert.equal(masks, 1, "repeated passes reuse the ad's mask");
    assert.equal(observed, 1);
  } finally {
    if (originalDocument === undefined) delete globalThis.document;
    else globalThis.document = originalDocument;
  }
});

test("damage stays off through intro, reveal, and its fade-out, then resumes", () => {
  const originalDocument = globalThis.document;
  let scene = null;
  let wakes = 0;
  globalThis.document = { querySelector: () => scene };
  const controller = {
    awaitingRevealValue: true,
    scenesBlocked: BlackholeController.prototype.scenesBlocked,
    setIntensity: BlackholeController.prototype.setIntensity,
    reset() {
      this.requested = 0;
      this.level = 0;
    },
    wake() {
      wakes++;
    },
  };
  try {
    controller.setIntensity(25);
    assert.equal(
      controller.requested,
      0,
      "initial render waits for completion",
    );
    for (const activeScene of ["intro", "reveal"]) {
      scene = activeScene;
      controller.setIntensity(100);
      assert.equal(controller.requested, 0, "polls cannot damage either scene");
    }
    BlackholeController.prototype.revealComplete.call(controller);
    assert.equal(
      controller.requested,
      0,
      "saved dismissal still waits for fade-out",
    );
    scene = null;
    controller.setIntensity(controller.latestIntensity);
    assert.equal(
      controller.requested,
      1,
      "latest damage resumes after removal",
    );
    assert.equal(wakes, 1);
    scene = "preview";
    controller.setIntensity(75);
    assert.equal(
      controller.requested,
      0,
      "an open story scene cannot be damaged",
    );
    scene = null;
    controller.setIntensity(controller.latestIntensity);
    assert.equal(controller.requested, 0.75);
  } finally {
    if (originalDocument === undefined) delete globalThis.document;
    else globalThis.document = originalDocument;
  }
});

test("story scenes never become disintegration surfaces", () => {
  const originalDocument = globalThis.document;
  try {
    for (const sceneClass of [".visual-novel", ".buku-x3-reveal"]) {
      let measured = 0;
      const scene = {
        matches: () => false,
        closest: (selector) => selector.split(", ").includes(sceneClass),
        getBoundingClientRect: () => {
          throw new Error("Story scene must not be measured or masked");
        },
      };
      const page = {
        id: "page",
        matches: () => false,
        closest: () => null,
        getBoundingClientRect: () => {
          measured++;
          return { width: 0, height: 0 };
        },
      };
      globalThis.document = {
        body: { children: [page] },
        querySelectorAll: () => [],
      };
      const controller = { surfaces: new Map(), element: {} };
      BlackholeController.prototype.collectSurfaces.call(controller);
      // Preview scenes arrive dynamically after blackhole initialization.
      document.body.children.push(scene);
      BlackholeController.prototype.collectSurfaces.call(controller);
      assert.equal(measured, 2, "normal page surfaces are still processed");
      assert.equal(controller.surfaces.size, 0);
    }
  } finally {
    if (originalDocument === undefined) delete globalThis.document;
    else globalThis.document = originalDocument;
  }
});

test("decorative artwork erodes with its card instead of being shielded", () => {
  const originalDocument = globalThis.document;
  const box = (left, top, width, height) => ({
    left,
    top,
    width,
    height,
    right: left + width,
    bottom: top + height,
  });
  const image = (decorative) => ({
    closest: (selector) =>
      decorative && selector === "[data-blackhole-decorative]" ? {} : null,
    matches: () => true,
    getClientRects: () => [box(20, 20, 100, 140)],
  });
  const art = image(true);
  const button = image(false);
  const originalNodeFilter = globalThis.NodeFilter;
  globalThis.NodeFilter = { SHOW_TEXT: 4 };
  try {
    globalThis.document = {
      createTreeWalker: () => ({ nextNode: () => false }),
      createRange: () => ({}),
    };
    const ad = {
      matches: () => false,
      querySelectorAll: () => [art, button],
    };
    const rects = BlackholeController.prototype.protectedRects.call(
      { localRect: BlackholeController.prototype.localRect },
      ad,
      box(0, 0, 310, 480),
    );
    assert.equal(rects.length, 1, "only the undecorated image is shielded");
  } finally {
    globalThis.NodeFilter = originalNodeFilter;
    if (originalDocument === undefined) delete globalThis.document;
    else globalThis.document = originalDocument;
  }
});
