import test from "node:test";
import assert from "node:assert/strict";
import VisualNovelController from "../../app/javascript/controllers/visual_novel_controller.js";

test("both explosions shake only the fixed scene without hiding its UI", () => {
  let cancelled = 0;
  const animations = [];
  const controller = {
    reduceMotion: false,
    shakeLinesValue: [1, 6],
    element: {
      animate(frames, options) {
        animations.push({ frames, options });
        return {
          cancel() {
            cancelled++;
          },
        };
      },
    },
  };
  for (const index of [1, 6]) {
    controller.index = index;
    VisualNovelController.prototype._shake.call(controller);
  }
  assert.equal(animations.length, 2);
  assert.equal(cancelled, 1);
  for (const { frames, options } of animations) {
    assert.equal(options.duration, 560);
    assert.deepEqual(frames.at(-1), { translate: "0 0" });
    assert.ok(
      frames.every((frame) => Object.keys(frame).join() === "translate"),
    );
  }
});

test("ordinary dialogue and reduced motion do not shake", () => {
  const controller = {
    index: 0,
    reduceMotion: false,
    shakeLinesValue: [1, 6],
    element: {
      animate() {
        assert.fail("unexpected shake");
      },
    },
  };
  VisualNovelController.prototype._shake.call(controller);
  controller.index = 1;
  controller.reduceMotion = true;
  VisualNovelController.prototype._shake.call(controller);
});
