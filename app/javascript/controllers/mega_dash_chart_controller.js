import { Controller } from "@hotwired/stimulus";
import Chart from "chart.js/auto";

export default class extends Controller {
  static targets = ["volume", "latency", "backlog"];
  static values = {
    data: Array,
    latencyUnit: { type: String, default: "h" },
    backlogLabel: { type: String, default: "Open" },
  };

  connect() {
    if (!this.hasDataValue || this.dataValue.length === 0) return;

    const labels = this.dataValue.map((row) => row.date);
    const salmon = this.color("--color-brand-salmon", "#ff8d9d");
    const blue = this.color("--color-brand-blue", "#95dbff");
    const lilac = this.color("--color-brand-lilac", "#ebb7ff");
    const peach = this.color("--color-brand-peach", "#ffd598");

    this.charts = [
      this.bars(this.volumeTarget, labels, [
        this.dataset("Arrived", "arrived", salmon),
        this.dataset("Decided", "decided", blue),
      ]),
      this.bars(
        this.latencyTarget,
        labels,
        [this.dataset("Median", "latency_hours", lilac)],
        this.latencyUnitValue,
      ),
    ];

    if (this.hasBacklogTarget) {
      this.charts.push(
        this.bars(this.backlogTarget, labels, [
          this.dataset(this.backlogLabelValue, "backlog", peach),
        ]),
      );
    }
  }

  disconnect() {
    this.charts?.forEach((chart) => chart.destroy());
  }

  color(token, fallback) {
    return (
      getComputedStyle(document.documentElement)
        .getPropertyValue(token)
        .trim() || fallback
    );
  }

  dataset(label, key, color) {
    return {
      label,
      data: this.dataValue.map((row) => row[key] ?? 0),
      backgroundColor: color,
      borderRadius: 2,
      borderWidth: 0,
    };
  }

  bars(canvas, labels, datasets, suffix = "") {
    return new Chart(canvas, {
      type: "bar",
      data: { labels, datasets },
      options: {
        maintainAspectRatio: false,
        responsive: true,
        plugins: {
          legend: {
            display: datasets.length > 1,
            labels: { color: "rgba(255,255,255,.75)", boxWidth: 10 },
          },
          tooltip: { mode: "index", intersect: false },
        },
        scales: {
          x: {
            ticks: { color: "rgba(255,255,255,.5)", maxTicksLimit: 8 },
            grid: { display: false },
          },
          y: {
            beginAtZero: true,
            ticks: {
              color: "rgba(255,255,255,.5)",
              maxTicksLimit: 5,
              callback: (value) => `${value}${suffix}`,
            },
            grid: { color: "rgba(255,255,255,.06)" },
          },
        },
      },
    });
  }
}
