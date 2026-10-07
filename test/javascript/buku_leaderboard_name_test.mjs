import test from "node:test";
import assert from "node:assert/strict";
import BukuLeaderboardNameController from "../../app/javascript/controllers/buku_leaderboard_name_controller.js";

globalThis.window = { matchMedia: () => ({ matches: false }) };

function nameController({ scrollWidth, clientWidth = 100 }) {
  const classes = new Set();
  const scrolls = [];
  const element = {
    scrollWidth,
    clientWidth,
    scrollLeft: 0,
    classList: {
      toggle(name, on) {
        if (on) classes.add(name);
        else classes.delete(name);
      },
    },
    getBoundingClientRect: () => ({ left: 0, width: clientWidth }),
    scrollTo({ left }) {
      scrolls.push(left);
      element.scrollLeft = left;
    },
  };
  const controller = Object.create(BukuLeaderboardNameController.prototype);
  // Stimulus defines `element` as a getter, so shadow it on the instance.
  Object.defineProperty(controller, "element", { value: element });
  controller.end = false;
  return { controller, element, classes, scrolls };
}

test("a cut-off name fades whichever side still has hidden text", () => {
  const { controller, element, classes } = nameController({ scrollWidth: 180 });
  controller.update();
  assert.deepEqual([...classes], ["buku-leaderboard__name--fade-end"]);
  element.scrollLeft = 40;
  controller.update();
  assert.deepEqual([...classes].sort(), [
    "buku-leaderboard__name--fade-end",
    "buku-leaderboard__name--fade-start",
  ]);
  element.scrollLeft = 80;
  controller.update();
  assert.deepEqual([...classes], ["buku-leaderboard__name--fade-start"]);
});

test("a name that fits never fades or scrolls", () => {
  const { controller, classes, scrolls } = nameController({ scrollWidth: 100 });
  controller.update();
  controller.track({ clientX: 95 });
  controller.reveal();
  assert.equal(classes.size, 0);
  assert.deepEqual(scrolls, []);
});

test("hovering the right half scrolls to the end once, and back on the left or leave", () => {
  const { controller, scrolls } = nameController({ scrollWidth: 180 });
  controller.track({ clientX: 80 });
  controller.track({ clientX: 90 });
  controller.track({ clientX: 70 });
  assert.deepEqual(
    scrolls,
    [80],
    "repeated mousemoves must not restart the scroll",
  );
  controller.track({ clientX: 20 });
  assert.deepEqual(scrolls, [80, 0]);
  controller.reveal();
  controller.reset();
  assert.deepEqual(scrolls, [80, 0, 80, 0]);
});
