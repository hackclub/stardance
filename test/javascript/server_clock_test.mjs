import test from "node:test";
import assert from "node:assert/strict";
import CountdownController from "../../app/javascript/controllers/countdown_controller.js";
import {
  ServerClock,
  serverClock,
} from "../../app/javascript/lib/server_clock.js";

const origin = Date.parse("2026-10-26T12:00:00Z");

test("server time advances monotonically despite OS clock jumps forward and backward", async (t) => {
  let elapsed = 100;
  const clock = new ServerClock({
    monotonic: () => elapsed,
    fetchTime: async () => ({
      ok: true,
      json: async () => ({ now: new Date(origin).toISOString(), ended: false }),
    }),
  });
  await clock.sync();
  t.mock.method(Date, "now", () => origin + 86400000);
  elapsed += 1000;
  assert.equal(clock.now(), origin + 1000);
  Date.now.mock.mockImplementation(() => origin - 86400000);
  elapsed += 1000;
  assert.equal(clock.now(), origin + 2000);
});

test("initial sync never uses the device clock and compensates for round-trip latency", async () => {
  let elapsed = 0;
  const clock = new ServerClock({
    monotonic: () => elapsed,
    fetchTime: async () => {
      elapsed = 200;
      return {
        ok: true,
        json: async () => ({
          now: new Date(origin).toISOString(),
          ended: false,
        }),
      };
    },
  });
  assert.ok(Number.isNaN(clock.now()));
  await clock.sync();
  assert.equal(clock.now(), origin + 100);
});

test("all clocks share an in-flight request", async () => {
  let finish;
  let calls = 0;
  const clock = new ServerClock({
    fetchTime: () => {
      calls++;
      return new Promise((resolve) => {
        finish = resolve;
      });
    },
  });
  const first = clock.sync();
  const second = clock.sync();
  assert.equal(first, second);
  finish({
    ok: true,
    json: async () => ({ now: new Date(origin).toISOString(), ended: false }),
  });
  await first;
  assert.equal(calls, 1);
});

test("failed synchronization retains only the previous monotonic anchor", async () => {
  let elapsed = 0;
  const clock = new ServerClock({
    monotonic: () => elapsed,
    fetchTime: async () => {
      throw new Error("offline");
    },
  });
  assert.equal(await clock.sync(), null);
  assert.ok(Number.isNaN(clock.now()));
  clock.anchor = { server: origin, local: 0 };
  elapsed = 2000;
  assert.equal(await clock.sync(), null);
  assert.equal(clock.now(), origin + 2000);
});

test("resume discards a stale sample before resynchronizing after sleep", async (t) => {
  let finish;
  const originalDocument = globalThis.document;
  globalThis.document = { hidden: false };
  t.after(() => {
    globalThis.document = originalDocument;
  });
  const clock = new ServerClock({
    monotonic: () => 0,
    fetchTime: () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
  });
  clock.anchor = { server: origin, local: 0 };
  clock.resume();
  assert.ok(Number.isNaN(clock.now()));
  finish({
    ok: true,
    json: async () => ({
      now: new Date(origin + 3600000).toISOString(),
      ended: true,
    }),
  });
  await clock.pending;
  assert.equal(clock.now(), origin + 3600000);
});

test("the rendered countdown stays on server time when the OS clock changes", async (t) => {
  let elapsed = 0;
  const clock = new ServerClock({ monotonic: () => elapsed });
  clock.anchor = { server: origin, local: 0 };
  t.mock.method(serverClock, "now", () => clock.now());
  t.mock.method(Date, "now", () => origin + 86400000);
  const c = {
    resetAtValue: new Date(origin + 3000).toISOString(),
    clockValue: true,
    element: {
      classList: {
        toggle(name, active) {
          c.urgent = active;
        },
      },
    },
  };
  const render = () => {
    CountdownController.prototype.render.call(c);
    return c.element.innerHTML.replace(/<[^>]*>/g, "");
  };
  assert.equal(render(), "00:00:00:03");
  assert.equal(c.urgent, true);
  elapsed = 1000;
  Date.now.mock.mockImplementation(() => origin - 86400000);
  assert.equal(render(), "00:00:00:02");
});
