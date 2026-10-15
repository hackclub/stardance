import { Controller } from "@hotwired/stimulus";
import Chart from "chart.js/auto";

export default class extends Controller {
  static targets = ["flow", "breakdown"];
  static values = {
    flow: Array,
    breakdown: Array,
  };

  connect() {
    this.charts = [this.renderFlowChart(), this.renderBreakdownChart()].filter(
      Boolean,
    );
  }

  disconnect() {
    this.charts?.forEach((chart) => chart.destroy());
  }

  renderFlowChart() {
    if (!this.hasFlowTarget) return null;

    return new Chart(this.flowTarget, {
      type: "bar",
      data: {
        labels: this.flowValue.map((row) => row.date),
        datasets: [
          {
            label: "Issued",
            data: this.flowValue.map((row) => row.issued),
            backgroundColor: "#81FFFF",
          },
          {
            label: "Spent",
            data: this.flowValue.map((row) => row.spent),
            backgroundColor: "#FF8D9D",
          },
          {
            type: "line",
            label: "Net",
            data: this.flowValue.map((row) => row.net),
            borderColor: "#FFE564",
            backgroundColor: "#FFE564",
            pointRadius: 2,
            tension: 0.25,
          },
        ],
      },
      options: this.chartOptions("Date"),
    });
  }

  renderBreakdownChart() {
    if (!this.hasBreakdownTarget) return null;

    return new Chart(this.breakdownTarget, {
      type: "bar",
      data: {
        labels: this.breakdownValue.map((row) => row.label),
        datasets: [
          {
            label: "Issued",
            data: this.breakdownValue.map((row) => row.issued),
            backgroundColor: "#95DBFF",
          },
          {
            label: "Spent",
            data: this.breakdownValue.map((row) => row.spent),
            backgroundColor: "#EBB7FF",
          },
        ],
      },
      options: {
        ...this.chartOptions("Source"),
        indexAxis: "y",
      },
    });
  }

  chartOptions(axisTitle) {
    return {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { labels: { color: "#FFFCF4" } },
      },
      scales: {
        x: {
          title: { display: true, text: axisTitle, color: "#83828D" },
          ticks: { color: "#AFB2C1" },
          grid: { color: "rgba(175, 178, 193, 0.12)" },
        },
        y: {
          beginAtZero: true,
          ticks: { color: "#AFB2C1" },
          grid: { color: "rgba(175, 178, 193, 0.12)" },
        },
      },
    };
  }
}
