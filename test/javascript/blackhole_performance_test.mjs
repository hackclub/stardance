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

test("small scrolls reuse meshes, while large jumps and resizing rebuild them", () => {
  const c = controller();
  const tall = { ...rect, height: 5000 };
  const initial = c.fragmentCells(tall, 9, 31);
  for (let offset = 10; offset <= 120; offset += 10)
    assert.equal(c.fragmentCells({ ...tall, top: -offset }, 9, 31), initial);
  const jumped = c.fragmentCells({ ...tall, top: -600 }, 9, 31);
  assert.notEqual(jumped, initial);
  const resized = c.fragmentCells({ ...tall, top: -600, width: 800 }, 9, 31);
  assert.notEqual(resized, jumped);
  assert.ok(
    resized.length < 20000,
    "tall pages must not allocate a full-page mesh",
  );
});

test("diagonal scroll reversals preserve visible polygons and keep one mesh per surface", () => {
  const c = controller();
  const normalize = (cells, rect) =>
    cells
      .filter(
        ({ cx, cy }) =>
          cx >= -rect.left &&
          cx <= c.width - rect.left &&
          cy >= -rect.top &&
          cy <= c.height - rect.top,
      )
      .map(({ cx, cy, vertices }) => [
        cx,
        cy,
        vertices.map((point) => point.map((n) => n.toFixed(6))).sort(),
      ]);
  for (const [left, top] of [
    [-200, -300],
    [-250, -350],
    [-210, -310],
    [-20, -30],
    [-800, -1200],
  ]) {
    const rect = { left, top, width: 3000, height: 5000 };
    const actual = normalize(c.fragmentCells(rect, 9, 31), rect);
    const expected = normalize(controller().fragmentCells(rect, 9, 31), rect);
    assert.equal(actual.length, expected.length);
    for (let i = 0; i < actual.length; i++)
      assert.deepEqual(actual[i], expected[i]);
    assert.equal(c.fragmentMeshes.size, 1);
  }
});

test("removed surfaces release their meshes, fields, and text copies", () => {
  const previousDocument = globalThis.document;
  globalThis.document = { querySelectorAll: () => [], body: { children: [] } };
  try {
    const c = controller();
    let removed = 0,
      unobserved = 0;
    const element = { isConnected: false };
    const removable = () => ({ remove: () => removed++ });
    c.surfaces = new Map([
      [
        element,
        {
          geometry: { seed: 31 },
          clip: removable(),
          textClip: removable(),
          textCopy: removable(),
        },
      ],
    ]);
    c.surfaceResize = { unobserve: () => unobserved++ };
    c.fragmentMeshes = new Map([[31, {}]]);
    c.fragmentFields = new Map([[31, {}]]);
    c.collectSurfaces();
    assert.equal(c.surfaces.size, 0);
    assert.equal(c.fragmentMeshes.size, 0);
    assert.equal(c.fragmentFields.size, 0);
    assert.equal(removed, 3);
    assert.equal(unobserved, 1);
  } finally {
    if (previousDocument === undefined) delete globalThis.document;
    else globalThis.document = previousDocument;
  }
});

test("scroll caching preserves visible polygon geometry without seams", () => {
  const c = controller();
  const tall = { ...rect, height: 5000 };
  c.fragmentCells(tall, 9, 31);
  for (const offset of [50, 120, 500, 650]) {
    const scrolled = { ...tall, top: -offset };
    const cached = c.fragmentCells(scrolled, 9, 31);
    const fresh = controller().fragmentCells(scrolled, 9, 31);
    const visible = (cells) =>
      cells
        .filter(
          ({ cx, cy }) =>
            cx >= 0 &&
            cx <= rect.width &&
            cy >= offset &&
            cy <= offset + c.height,
        )
        .map(({ cx, cy, vertices }) => [
          cx,
          cy,
          vertices.map((point) => point.map((n) => n.toFixed(6))).sort(),
        ]);
    const actual = visible(cached);
    const expected = visible(fresh);
    assert.equal(actual.length, expected.length);
    for (let index = 0; index < actual.length; index++)
      assert.deepEqual(actual[index], expected[index]);
  }
});

test("scrolling a Phantom-sized card reuses its decay field but respects changed text bounds", () => {
  const previousStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = () => ({ zIndex: "5", position: "relative" });
  try {
    const c = controller();
    c.textRevision = 1;
    c.dirty = true;
    let textLeft = 20;
    c.protectedRects = () => [
      { left: textLeft, right: 280, top: 250, bottom: 300, kind: "text" },
    ];
    const element = {};
    const surface = { card: true, seed: 31 };
    const ad = { left: 850, top: 150, width: 310, height: 480 };
    const geometry = c.surfaceGeometry(element, surface, ad);
    const field = c.fragmentField(
      ad,
      9,
      geometry.seed,
      geometry.protectedRects,
      geometry.excludedRects,
    );
    const scrolled = { ...ad, top: 50 };
    const next = c.surfaceGeometry(element, surface, scrolled);
    assert.equal(next.protectedRects, geometry.protectedRects);
    assert.equal(next.excludedRects, geometry.excludedRects);
    assert.equal(
      c.fragmentField(
        scrolled,
        9,
        next.seed,
        next.protectedRects,
        next.excludedRects,
      ),
      field,
    );
    textLeft = 30;
    const changed = c.surfaceGeometry(element, surface, scrolled);
    assert.notEqual(changed.protectedRects, next.protectedRects);
    assert.notEqual(
      c.fragmentField(
        scrolled,
        9,
        changed.seed,
        changed.protectedRects,
        changed.excludedRects,
      ),
      field,
    );
  } finally {
    if (previousStyle) globalThis.getComputedStyle = previousStyle;
    else delete globalThis.getComputedStyle;
  }
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

test("throttled animation masks keep scheduling until the final state is painted", () => {
  let cuts = 0;
  let wakes = 0;
  const c = {
    level: 0.25,
    requested: 0.25,
    lastTime: 100,
    lastMask: 100,
    maskInterval: 100,
    maskDirty: true,
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
  assert.equal(c.maskDirty, false);
  assert.equal(wakes, 2);
});

test("scroll and layout invalidations bypass both throttles even on slow machines", () => {
  let cuts = 0;
  const c = {
    level: 0.9,
    requested: 0.9,
    lastTime: 100,
    lastMask: 100,
    maskInterval: 160,
    dirty: true,
    particles: [],
    reducedMotion: { matches: false },
    cutSurfaces() {
      cuts++;
    },
    emitAmbientDust() {},
    draw() {},
    wake() {},
  };
  for (const time of [110, 120, 130]) {
    c.dirty = true;
    BlackholeController.prototype.tick.call(c, time);
    assert.equal(
      c.lastMask,
      time,
      "scroll masks must track each new viewport position",
    );
    assert.equal(c.dirty, false);
  }
  assert.equal(cuts, 3);
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

test("page text retains document coordinates across vertical and horizontal scrolling", () => {
  const c = controller();
  const copy = {
    style: {},
    classList: {
      toggle(name, fixed) {
        assert.equal(fixed, false);
      },
    },
  };
  const element = { scrollTop: 0, scrollLeft: 0 };
  const surface = {
    textCopy: copy,
    geometry: { viewportText: false },
    scrollCopies: [],
  };
  c.positionDamagedText(
    element,
    surface,
    { left: 200, top: 600 },
    { left: 0, top: 0 },
  );
  assert.equal(copy.style.top, "600px");
  assert.equal(copy.style.left, "200px");
  c.positionDamagedText(
    element,
    surface,
    { left: 120, top: 100 },
    { left: -80, top: -500 },
  );
  assert.equal(
    copy.style.top,
    "600px",
    "native scrolling moves the copy, not a delayed top update",
  );
  assert.equal(copy.style.left, "200px");
});

test("fixed sidebar text stays viewport anchored and nested scroll offsets are mirrored", () => {
  const c = controller();
  const copy = {
    style: {},
    classList: {
      toggle(name, fixed) {
        assert.equal(fixed, true);
      },
    },
  };
  const original = { scrollTop: 45, scrollLeft: 12 };
  const clone = {};
  const surface = {
    textCopy: copy,
    geometry: { viewportText: true },
    scrollCopies: [[original, clone]],
  };
  c.positionDamagedText(
    original,
    surface,
    { left: 20, top: 300 },
    { left: -80, top: -500 },
  );
  assert.equal(copy.style.top, "300px");
  assert.equal(copy.style.left, "20px");
  assert.equal(copy.scrollTop, 45);
  assert.equal(clone.scrollTop, 45);
  assert.equal(clone.scrollLeft, 12);
});

test("viewport anchoring includes fixed and sticky ancestors, not ordinary page text", () => {
  const previousStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element) => ({ position: element.position });
  try {
    const c = controller();
    for (const position of ["fixed", "sticky", "relative", "static"]) {
      const element = {
        position: "static",
        parentElement: { position, parentElement: null },
      };
      assert.equal(
        c.textFollowsViewport(element),
        ["fixed", "sticky"].includes(position),
      );
    }
  } finally {
    if (previousStyle) globalThis.getComputedStyle = previousStyle;
    else delete globalThis.getComputedStyle;
  }
});
