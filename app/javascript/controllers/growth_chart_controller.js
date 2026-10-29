import { Controller } from "@hotwired/stimulus";
import Chart from "chart.js/auto";

// One growth-model chart: stacked bars when `stacked`, lines otherwise.
// `series` names the row keys to plot and the brand colour token for each.
// A series marked `dashed` draws as a dashed line, for projections.
// `compact` drops the legend and date labels for the small-multiple charts.
export default class extends Controller {
  static values = {
    rows: Array,
    series: Array,
    stacked: { type: Boolean, default: false },
    percent: { type: Boolean, default: false },
    compact: { type: Boolean, default: false },
  };

  connect() {
    if (this.rowsValue.length === 0) return;

    const styles = getComputedStyle(document.documentElement);
    const datasets = this.seriesValue.map(({ key, label, color, dashed }) => {
      const value = styles.getPropertyValue(color).trim();
      return {
        label,
        data: this.rowsValue.map((row) =>
          this.percentValue && row[key] != null ? row[key] * 100 : row[key],
        ),
        backgroundColor: value,
        borderColor: value,
        borderWidth: this.stackedValue ? 0 : 2,
        borderDash: dashed ? [6, 4] : [],
        pointRadius: 0,
        spanGaps: true,
      };
    });

    this.chart = new Chart(this.element, {
      type: this.stackedValue ? "bar" : "line",
      data: { labels: this.rowsValue.map((row) => row.date), datasets },
      options: {
        maintainAspectRatio: false,
        responsive: true,
        interaction: { mode: "index", intersect: false },
        plugins: {
          legend: {
            display: !this.compactValue,
            labels: { color: "rgba(255,255,255,.75)", boxWidth: 10 },
          },
        },
        scales: {
          x: {
            stacked: this.stackedValue,
            ticks: {
              display: !this.compactValue,
              color: "rgba(255,255,255,.5)",
              maxTicksLimit: 6,
            },
            grid: { display: false },
          },
          y: {
            stacked: this.stackedValue,
            beginAtZero: true,
            max: this.percentValue ? 100 : undefined,
            ticks: {
              color: "rgba(255,255,255,.5)",
              maxTicksLimit: 5,
              callback: (value) => (this.percentValue ? `${value}%` : value),
            },
            grid: { color: "rgba(255,255,255,.06)" },
          },
        },
      },
    });
  }

  // Compact charts get their legend and dates back while maximised.
  fullscreenChanged() {
    if (!this.chart || !this.compactValue) return;

    const maximised =
      document.fullscreenElement?.contains(this.element) ?? false;
    this.chart.options.plugins.legend.display = maximised;
    this.chart.options.scales.x.ticks.display = maximised;
    this.chart.update();
  }

  disconnect() {
    this.chart?.destroy();
  }
}
