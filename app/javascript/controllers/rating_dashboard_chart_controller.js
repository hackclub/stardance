import { Controller } from "@hotwired/stimulus";
import Chart from "chart.js/auto";

export default class extends Controller {
  static targets = ["queue", "throughput", "rating", "payment"];
  static values = { data: Array };

  connect() {
    if (!this.hasDataValue || this.dataValue.length === 0) return;

    this.charts = [];
    const labels = this.dataValue.map((row) => row.date);
    const mint = this.color("--color-brand-mint", "#81ffff");
    const lilac = this.color("--color-brand-lilac", "#ebb7ff");
    const yellow = this.color("--color-brand-yellow", "#ffe564");
    const salmon = this.color("--color-brand-salmon", "#ff8d9d");

    this.charts.push(
      this.line(this.queueTarget, labels, [
        this.dataset("Waiting", "queue_size", lilac),
      ]),
      this.line(this.throughputTarget, labels, [
        this.dataset("Entered voting", "entered", lilac),
        this.dataset("Reached 12 votes", "completed", mint),
        this.dataset("Paid", "paid", yellow),
      ]),
      this.line(
        this.ratingTarget,
        labels,
        [this.dataset("Median hours", "rating_median_hours", mint)],
        "h",
      ),
      this.line(
        this.paymentTarget,
        labels,
        [this.dataset("Median hours", "payment_median_hours", salmon)],
        "h",
      ),
    );
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
      data: this.dataValue.map((row) => row[key] ?? null),
      borderColor: color,
      backgroundColor: `${color}22`,
      fill: true,
      pointRadius: 2,
      spanGaps: true,
      tension: 0.3,
    };
  }

  line(canvas, labels, datasets, suffix = "") {
    return new Chart(canvas, {
      type: "line",
      data: { labels, datasets },
      options: {
        maintainAspectRatio: false,
        responsive: true,
        plugins: {
          legend: { labels: { color: "rgba(255,255,255,.75)" } },
          tooltip: { mode: "index", intersect: false },
        },
        scales: {
          x: {
            ticks: { color: "rgba(255,255,255,.5)", maxTicksLimit: 10 },
            grid: { color: "rgba(255,255,255,.06)" },
          },
          y: {
            beginAtZero: true,
            ticks: {
              color: "rgba(255,255,255,.5)",
              callback: (value) => `${value}${suffix}`,
            },
            grid: { color: "rgba(255,255,255,.06)" },
          },
        },
      },
    });
  }
}
