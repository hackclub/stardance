import test from "node:test";
import assert from "node:assert/strict";
import BukuActivityChartController from "../../app/javascript/controllers/buku_activity_chart_controller.js";

test("daily chart stacks both team counts with brand colors and whole-number axes", () => {
  const controller = {
    dataValue: [
      { date: "2026-09-22", buku: 3, bean: 5 },
      { date: "2026-09-23", buku: 0, bean: 2 },
    ],
    color: (token) => token,
  };
  const config =
    BukuActivityChartController.prototype.configuration.call(controller);
  assert.equal(config.type, "bar");
  assert.deepEqual(config.data.labels, ["2026-09-22", "2026-09-23"]);
  assert.deepEqual(
    config.data.datasets.map((series) => series.data),
    [
      [3, 0],
      [5, 2],
    ],
  );
  assert.deepEqual(
    config.data.datasets.map((series) => series.backgroundColor),
    ["--color-brand-lilac", "--color-brand-yellow"],
  );
  assert.equal(config.options.scales.x.stacked, true);
  assert.equal(config.options.scales.y.stacked, true);
  assert.equal(config.options.scales.y.ticks.precision, 0);
  assert.equal(config.options.animation, false);
});

test("chart is destroyed when navigating away", () => {
  let destroyed = false;
  BukuActivityChartController.prototype.disconnect.call({
    chart: {
      destroy() {
        destroyed = true;
      },
    },
  });
  assert.equal(destroyed, true);
});
