import test from "node:test";
import assert from "node:assert/strict";
import CompleteReviewController from "../../app/javascript/controllers/certification/ysws/complete_review_controller.js";

function setup(save) {
  const controller = Object.create(CompleteReviewController.prototype);
  const button = {
    disabled: false,
    childNodes: ["Complete & next"],
    replaceChildren(...children) {
      this.childNodes = children;
    },
  };
  const control = { disabled: false };
  Object.defineProperties(controller, {
    buttonTarget: { value: button },
    element: { value: { querySelectorAll: () => [control] } },
  });
  const flashes = [];
  controller.showFlash = (message) => flashes.push(message);
  globalThis.confirm = () => true;
  globalThis.document = { activeElement: null };
  globalThis.HTMLTextAreaElement = class {};
  globalThis.CustomEvent = class {
    constructor(type, { detail }) {
      this.type = type;
      this.detail = detail;
    }
  };
  globalThis.window = {
    dispatchEvent(event) {
      assert.equal(event.type, "devlog-review:flush");
      event.detail.pending.push(save);
    },
  };
  let submitted = false;
  const form = { submit: () => (submitted = true) };
  const event = { currentTarget: form, preventDefault() {} };
  return {
    controller,
    button,
    control,
    flashes,
    event,
    submitted: () => submitted,
  };
}

test("completion waits for pending edits before submitting the flow form", async () => {
  let finishSave;
  const context = setup(new Promise((resolve) => (finishSave = resolve)));
  const completion = context.controller.complete(context.event);
  assert.equal(context.submitted(), false);
  assert.equal(context.control.disabled, true);
  // A browser clears currentTarget after the synchronous event handler returns.
  context.event.currentTarget = null;
  finishSave(true);
  await completion;
  assert.equal(context.submitted(), true);
});

test("a failed devlog save prevents completion and restores editing", async () => {
  const context = setup(Promise.resolve(false));
  await context.controller.complete(context.event);
  assert.equal(context.submitted(), false);
  assert.equal(context.button.disabled, false);
  assert.equal(context.control.disabled, false);
  assert.match(context.flashes[0], /could not be saved/);
});
