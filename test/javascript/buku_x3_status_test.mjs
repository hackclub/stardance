import test from "node:test";
import assert from "node:assert/strict";
import BukuX3StatusController from "../../app/javascript/controllers/buku_x3_status_controller.js";

test("role reveal toggles on tap and Escape dismisses it", () => {
  const attributes = new Map();
  let pressed;
  let blurred = false;
  const controller = {
    element: {
      toggleAttribute(name) {
        if (attributes.has(name)) attributes.delete(name);
        else attributes.set(name, "");
        return attributes.has(name);
      },
      removeAttribute(name) {
        attributes.delete(name);
      },
    },
    toggleTarget: {
      setAttribute(name, value) {
        pressed = value;
      },
      blur() {
        blurred = true;
      },
    },
  };
  const toggle = () =>
    BukuX3StatusController.prototype.toggleRole.call(controller);
  toggle();
  assert.equal(pressed, "true");
  assert.ok(attributes.has("data-role-open"));
  toggle();
  assert.equal(pressed, "false");
  assert.equal(attributes.has("data-role-open"), false);
  toggle();
  BukuX3StatusController.prototype.dismissRole.call(controller);
  assert.equal(pressed, "false");
  assert.equal(attributes.has("data-role-open"), false);
  assert.equal(blurred, true);
});

test("team counters follow live totals and retain them between updates", () => {
  const controller = {
    hasMeterTarget: true,
    meterTarget: { setAttribute() {}, style: { setProperty() {} } },
    amountTarget: {},
    bukuHoursTarget: {},
    beanHoursTarget: {},
    liveHoursValue: { buku: 12, bean: 34 },
  };
  const update = (detail) =>
    BukuX3StatusController.prototype.update.call(controller, { detail });
  update({ percent: 25, hours: { buku: 1234.5, bean: 67 } });
  assert.equal(controller.bukuHoursTarget.textContent, "1,234.5");
  assert.equal(controller.beanHoursTarget.textContent, "67");
  update({ percent: 25 });
  assert.equal(controller.bukuHoursTarget.textContent, "1,234.5");
  assert.equal(controller.beanHoursTarget.textContent, "67");
  update({ percent: 35, hours: { buku: 500, bean: 0 } });
  assert.equal(controller.bukuHoursTarget.textContent, "500");
  assert.equal(controller.beanHoursTarget.textContent, "0");
});
