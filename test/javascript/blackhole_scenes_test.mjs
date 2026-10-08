import test from "node:test";
import assert from "node:assert/strict";
import BlackholeController from "../../app/javascript/controllers/blackhole_controller.js";

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
