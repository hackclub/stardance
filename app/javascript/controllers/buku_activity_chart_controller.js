import { Controller } from "@hotwired/stimulus";
import Chart from "chart.js/auto";

export default class extends Controller {
  static targets = ["canvas"];
  static values = { data: Array };

  connect() {
    this.chart = new Chart(this.canvasTarget, this.configuration());
  }

  disconnect() {
    this.chart?.destroy();
  }

  color(token) {
    return getComputedStyle(this.element).getPropertyValue(token).trim();
  }

  configuration() {
    const text = this.color("--color-brand-off-white");
    return {
      type: "bar",
      data: {
        labels: this.dataValue.map((day) => day.date),
        datasets: [
          { label: "buku bukus", key: "buku", token: "--color-brand-lilac" },
          { label: "beans", key: "bean", token: "--color-brand-yellow" },
        ].map(({ label, key, token }) => ({
          label,
          data: this.dataValue.map((day) => day[key]),
          backgroundColor: this.color(token),
          maxBarThickness: 40,
        })),
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        plugins: {
          legend: { labels: { color: text } },
          tooltip: { mode: "index", intersect: false },
        },
        scales: {
          x: {
            stacked: true,
            ticks: { color: text, maxTicksLimit: 7 },
            grid: { display: false },
          },
          y: {
            stacked: true,
            beginAtZero: true,
            suggestedMax: 1,
            ticks: { color: text, precision: 0 },
            grid: { color: this.color("--color-set-2-bg") },
          },
        },
      },
    };
  }
}
