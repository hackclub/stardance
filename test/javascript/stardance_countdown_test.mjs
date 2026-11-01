import test from "node:test";
import assert from "node:assert/strict";
import StardanceCountdownController from "../../app/javascript/controllers/stardance_countdown_controller.js";
import CountdownController from "../../app/javascript/controllers/countdown_controller.js";
import { serverClock } from "../../app/javascript/lib/server_clock.js";

const endsAt = "2026-10-31T23:59:59.999-04:00";
const explodesAt = "2026-11-01T12:00:00.000-05:00";

function controller() {
  const c = {
    hasLabelTarget: true,
    endsAtValue: endsAt,
    explodesAtValue: explodesAt,
    overrideAtValue: "",
    labelTarget: { textContent: "stardance ends in" },
    clockTargets: [0, 1].map(() => ({
      deadline: endsAt,
      getAttribute() {
        return this.deadline;
      },
      setAttribute(name, value) {
        assert.equal(name, "data-countdown-reset-at-value");
        this.deadline = value;
      },
    })),
  };
  c.render = StardanceCountdownController.prototype.render.bind(c);
  return c;
}

test("an open page switches both clocks and the caption at the original end time", () => {
  const c = controller();
  c.render(Date.parse(endsAt) - 1);
  assert.equal(c.labelTarget.textContent, "stardance ends in");
  assert.deepEqual(
    c.clockTargets.map((clock) => clock.deadline),
    [endsAt, endsAt],
  );

  c.render(Date.parse(endsAt));
  assert.equal(c.labelTarget.textContent, "stardance explodes in");
  assert.deepEqual(
    c.clockTargets.map((clock) => clock.deadline),
    [explodesAt, explodesAt],
  );
  c.render(Date.parse(explodesAt));
  assert.equal(c.labelTarget.textContent, "stardance explodes in");
});

test("fresh and resumed pages select the current stage from server time, including the DST change", (t) => {
  const midnight = Date.parse("2026-11-01T00:00:00-04:00");
  t.mock.method(serverClock, "now", () => midnight);
  t.mock.method(Date, "now", () => Date.parse(explodesAt) + 86400000);
  const c = controller();
  c.render();
  assert.equal(c.labelTarget.textContent, "stardance explodes in");

  const clock = {
    resetAtValue: c.clockTargets[0].deadline,
    clockValue: true,
    element: { classList: { toggle() {} } },
  };
  CountdownController.prototype.render.call(clock);
  assert.equal(clock.element.innerHTML.replace(/<[^>]*>/g, ""), "00:13:00:00");
});

test("no server clock sample preserves the server-rendered stage instead of guessing", (t) => {
  t.mock.method(serverClock, "now", () => NaN);
  const c = controller();
  c.render();
  assert.equal(c.labelTarget.textContent, "stardance ends in");
  assert.deepEqual(
    c.clockTargets.map((clock) => clock.deadline),
    [endsAt, endsAt],
  );
});

test("replay overrides the label and both clocks, then returns to the current stage", () => {
  const c = controller();
  const beforeEnd = Date.parse(endsAt) - 60000;
  const previewAt = new Date(beforeEnd + 3000).toISOString();
  c.overrideAtValue = previewAt;
  c.render(beforeEnd);
  assert.equal(c.labelTarget.textContent, "stardance explodes in");
  assert.deepEqual(
    c.clockTargets.map((clock) => clock.deadline),
    [previewAt, previewAt],
  );
  c.render(Date.parse(endsAt) + 1000);
  assert.deepEqual(
    c.clockTargets.map((clock) => clock.deadline),
    [previewAt, previewAt],
  );

  c.overrideAtValue = "";
  c.render(beforeEnd);
  assert.equal(c.labelTarget.textContent, "stardance ends in");
  assert.deepEqual(
    c.clockTargets.map((clock) => clock.deadline),
    [endsAt, endsAt],
  );
  c.render(Date.parse(endsAt) + 1000);
  assert.equal(c.labelTarget.textContent, "stardance explodes in");
  assert.deepEqual(
    c.clockTargets.map((clock) => clock.deadline),
    [explodesAt, explodesAt],
  );
});

test("navigation releases the clock subscription and interval", (t) => {
  const c = controller();
  let subscribed;
  let unsubscribed = false;
  t.mock.method(serverClock, "subscribe", (callback) => {
    subscribed = callback;
    return () => {
      unsubscribed = true;
    };
  });
  t.mock.method(serverClock, "now", () => Date.parse(endsAt) - 1000);
  t.mock.method(globalThis, "setInterval", () => 42);
  const clear = t.mock.method(globalThis, "clearInterval", () => {});
  StardanceCountdownController.prototype.connect.call(c);
  serverClock.now.mock.mockImplementation(() => Date.parse(endsAt) + 1000);
  subscribed();
  assert.equal(c.labelTarget.textContent, "stardance explodes in");
  StardanceCountdownController.prototype.disconnect.call(c);
  assert.equal(unsubscribed, true);
  assert.equal(clear.mock.calls[0].arguments[0], 42);
});
