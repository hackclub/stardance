import { Controller } from "@hotwired/stimulus";
import Chart from "chart.js/auto";

// Brand palette (docs/branding.md). Cycled when the top reviewer set is wider
// than the palette.
const PALETTE = [
  "#81FFFF", // mint
  "#EBB7FF", // lilac
  "#95DBFF", // blue
  "#FF8D9D", // salmon
  "#FFE564", // yellow
  "#FFD598", // peach
];

const MAX_SERIES = 10;

export default class extends Controller {
  static targets = ["canvas"];
  static values = {
    chart: Object, // { labels: [...], series: [{ name, data: [...] }] }
  };

  connect() {
    const { labels = [], series = [] } = this.chartValue || {};
    if (!series.length) return;

    const datasets = series.slice(0, MAX_SERIES).map((s, i) => {
      const color = PALETTE[i % PALETTE.length];
      return {
        label: s.name || "Unknown",
        data: s.data,
        borderColor: color,
        backgroundColor: color,
        tension: 0.3,
        pointRadius: 2,
      };
    });

    this.chart = new Chart(this.canvasTarget, {
      type: "line",
      data: { labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: "index", intersect: false },
        scales: {
          x: {
            grid: { color: "rgba(255, 255, 255, 0.1)" },
            ticks: { color: "rgba(255, 255, 255, 0.7)" },
          },
          y: {
            beginAtZero: true,
            ticks: { color: "rgba(255, 255, 255, 0.7)", precision: 0 },
            grid: { color: "rgba(255, 255, 255, 0.1)" },
          },
        },
        plugins: {
          legend: {
            labels: {
              boxWidth: 22,
              boxHeight: 8,
              color: "rgba(255, 255, 255, 0.7)",
              padding: 10,
            },
          },
        },
      },
    });
  }

  disconnect() {
    this.chart?.destroy();
  }
}
