import { Controller } from "@hotwired/stimulus";
import Chart from "chart.js/auto";

const PALETTE = [
  "#81FFFF", // cyan
  "#FFE564", // yellow
  "#FF8D9D", // salmon
  "#86efac", // green
  "#FFD598", // peach
  "#bef264", // lime
  "#EBB7FF", // lilac
  "#FFF8D5", // cream
  "#2DD4BF", // teal
  "#95DBFF", // blue
  "#A7F3D0", // mint green
  "#FDE68A", // gold
];

function hexToRgba(hex, alpha) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

const FORMATTERS = {
  hours: (ctx) => {
    const h = ctx.parsed.y;
    if (h === null) return "  no data";
    const d = Math.floor(h / 24),
      rem = Math.round(h % 24);
    return d > 0 ? `  ${d}d ${rem}h` : `  ${rem}h`;
  },
  net: (ctx) => {
    const v = ctx.parsed.y;
    return `  Net: ${v >= 0 ? "+" : ""}${v}`;
  },
  pct: (ctx) => `  ${ctx.parsed.y !== null ? ctx.parsed.y + "%" : "no data"}`,
};

export default class extends Controller {
  static targets = [
    "queueSize",
    "medianWait",
    "net",
    "throughput",
    "verdict",
    "rate",
    "participation",
    "reviewerPicker",
    "reviewerTotals",
    "reviewerDecisions",
    "reviewerReturned",
  ];
  static values = { data: Array, reviewerData: Array };

  connect() {
    this.charts = [];
    this.selectedReviewers = new Set();
    this.reviewerCharts = [];

    const gridColor = "rgba(255,255,255,0.06)";
    const tickFont = { family: "var(--font-family-sans)", size: 10 };
    const tickColor = "rgba(255,255,255,0.45)";
    this.cfg = {
      gridColor,
      xScale: {
        ticks: { color: tickColor, font: tickFont, maxTicksLimit: 10 },
        grid: { color: gridColor },
      },
      yScale: {
        ticks: { color: tickColor, font: tickFont, precision: 0 },
        grid: { color: gridColor },
      },
      legend: {
        labels: {
          color: "rgba(255,255,255,0.7)",
          font: { family: "var(--font-family-sans)", size: 11 },
          boxWidth: 12,
        },
      },
      tooltip: { mode: "index", intersect: false },
    };
    this.labels = this.hasDataValue ? this.dataValue.map((d) => d.date) : [];

    if (this.hasDataValue && this.dataValue.length > 0) {
      this.renderActivityCharts();
    }

    if (this.hasReviewerDataValue && this.reviewerDataValue.length > 0) {
      this.renderReviewerPicker();
      this.initReviewerCharts();
    }
  }

  #makeLine(canvas, datasets, extraOpts = {}) {
    const { xScale, yScale, legend, tooltip } = this.cfg;
    return new Chart(canvas, {
      type: "line",
      data: { labels: this.labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { labels: legend.labels }, tooltip },
        scales: { x: xScale, y: { ...yScale, min: 0 } },
        ...extraOpts,
      },
    });
  }

  #ds(label, data, borderColor, bgAlpha = 0.08, extra = {}) {
    return {
      label,
      data,
      borderColor,
      backgroundColor: borderColor.startsWith("#")
        ? hexToRgba(borderColor, bgAlpha)
        : borderColor.replace(")", `,${bgAlpha})`),
      fill: true,
      tension: 0.3,
      pointRadius: 2,
      ...extra,
    };
  }

  // Per-chart options for the charts that need a custom y-axis suffix, range,
  // tooltip formatter, or zero-line grid. The rest fall back to #makeLine's
  // defaults.
  #opts({ formatter, suffix, yMin = 0, yMax, zeroGrid = false } = {}) {
    const { xScale, yScale, legend, tooltip, gridColor } = this.cfg;
    const y = { ...yScale };
    if (yMin != null) y.min = yMin;
    if (yMax != null) y.max = yMax;
    if (suffix) y.ticks = { ...yScale.ticks, callback: (v) => `${v}${suffix}` };
    if (zeroGrid) {
      y.grid = {
        color: (ctx) =>
          ctx.tick.value === 0 ? "rgba(255,255,255,0.25)" : gridColor,
      };
    }
    return {
      plugins: {
        legend: { labels: legend.labels },
        tooltip: { ...tooltip, callbacks: { label: formatter } },
      },
      scales: { x: xScale, y },
    };
  }

  renderActivityCharts() {
    const data = this.dataValue;

    this.charts.push(
      this.#makeLine(this.queueSizeTarget, [
        this.#ds(
          "Queue size",
          data.map((d) => d.queue_size),
          "#FFD598",
          0.12,
        ),
      ]),

      this.#makeLine(
        this.medianWaitTarget,
        [
          this.#ds(
            "Median wait (hours)",
            data.map((d) => d.median_wait_hours ?? null),
            "#EBB7FF",
            0.08,
            { spanGaps: true },
          ),
        ],
        this.#opts({ formatter: FORMATTERS.hours, suffix: "h" }),
      ),

      this.#makeLine(
        this.netTarget,
        [
          {
            label: "Net (decisions − submissions)",
            data: data.map((d) => d.approved + d.returned - d.submitted),
            borderColor: "#81FFFF",
            borderWidth: 1.5,
            pointRadius: 2,
            tension: 0.3,
            fill: {
              target: "origin",
              above: "rgba(129,255,255,0.15)",
              below: "rgba(255,213,152,0.2)",
            },
          },
        ],
        this.#opts({ formatter: FORMATTERS.net, yMin: null, zeroGrid: true }),
      ),

      this.#makeLine(this.throughputTarget, [
        this.#ds(
          "Decisions",
          data.map((d) => d.approved + d.returned),
          "#81FFFF",
        ),
        this.#ds(
          "Submitted",
          data.map((d) => d.submitted),
          "#EBB7FF",
        ),
      ]),

      this.#makeLine(this.verdictTarget, [
        this.#ds(
          "Approved",
          data.map((d) => d.approved),
          "#81FFFF",
        ),
        this.#ds(
          "Returned",
          data.map((d) => d.returned),
          "#FFD598",
        ),
      ]),

      this.#makeLine(
        this.rateTarget,
        [
          this.#ds(
            "Rejection rate",
            data.map((d) => {
              const total = d.approved + d.returned;
              return total > 0
                ? parseFloat(((d.returned / total) * 100).toFixed(1))
                : null;
            }),
            "#FFE564",
            0.08,
            { spanGaps: true },
          ),
        ],
        this.#opts({ formatter: FORMATTERS.pct, suffix: "%", yMax: 100 }),
      ),

      this.#makeLine(this.participationTarget, [
        this.#ds(
          "Reviewers active",
          data.map((d) => d.unique_reviewers),
          "#86efac",
          0.1,
        ),
      ]),
    );
  }

  renderReviewerPicker() {
    const reviewers = this.reviewerDataValue;
    const wrapper = this.reviewerPickerTarget;

    const dropdown = document.createElement("div");
    dropdown.className = "ship-monitor__reviewer-dropdown";

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "ship-monitor__reviewer-dropdown-btn";
    btn.innerHTML =
      '<span data-label>Add reviewer to compare…</span><span class="ship-monitor__reviewer-dropdown-arrow">▾</span>';

    const panel = document.createElement("div");
    panel.className = "ship-monitor__reviewer-dropdown-panel";
    panel.hidden = true;

    const search = document.createElement("input");
    search.type = "text";
    search.placeholder = "Search reviewers…";
    search.className = "ship-monitor__reviewer-search";
    panel.appendChild(search);

    const list = document.createElement("ul");
    list.className = "ship-monitor__reviewer-list";

    reviewers.forEach((r, i) => {
      const color = PALETTE[i % PALETTE.length];
      const li = document.createElement("li");
      const label = document.createElement("label");
      label.className = "ship-monitor__reviewer-option";

      const cb = document.createElement("input");
      cb.type = "checkbox";

      cb.addEventListener("change", () => {
        if (cb.checked) {
          this.selectedReviewers.add(r.name);
          label.classList.add("is-checked");
          label.style.color = color;
        } else {
          this.selectedReviewers.delete(r.name);
          label.classList.remove("is-checked");
          label.style.color = "";
        }
        this.updateDropdownLabel(btn);
        this.updateReviewerCharts();
      });

      label.appendChild(cb);
      label.appendChild(document.createTextNode(r.name));
      li.appendChild(label);
      list.appendChild(li);
    });

    panel.appendChild(list);
    dropdown.appendChild(btn);
    dropdown.appendChild(panel);
    wrapper.appendChild(dropdown);

    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      panel.hidden = !panel.hidden;
      if (!panel.hidden) search.focus();
    });

    search.addEventListener("input", () => {
      const q = search.value.toLowerCase();
      [...list.children].forEach((li) => {
        li.hidden = !li
          .querySelector("label")
          .textContent.toLowerCase()
          .includes(q);
      });
    });

    this.closeDropdownFn = (e) => {
      if (!dropdown.contains(e.target)) panel.hidden = true;
    };
    document.addEventListener("click", this.closeDropdownFn);
  }

  updateDropdownLabel(btn) {
    const count = this.selectedReviewers.size;
    btn.querySelector("[data-label]").textContent =
      count === 0
        ? "Add reviewer to compare…"
        : `${count} reviewer${count !== 1 ? "s" : ""} selected`;
  }

  initReviewerCharts() {
    const targets = [this.reviewerDecisionsTarget, this.reviewerReturnedTarget];
    this.reviewerCharts = targets.map((canvas) => this.#makeLine(canvas, []));
    this.charts.push(...this.reviewerCharts);
  }

  updateReviewerCharts() {
    const reviewers = this.reviewerDataValue;
    const selected = reviewers.filter((r) =>
      this.selectedReviewers.has(r.name),
    );

    const lineDatasets = (field) =>
      selected.map((r) => {
        const i = reviewers.indexOf(r);
        const color = PALETTE[i % PALETTE.length];
        return {
          label: r.name,
          data: r.data.map((d) => (d[field] > 0 ? d[field] : null)),
          borderColor: color,
          borderWidth: 1.5,
          pointRadius: 0,
          pointHoverRadius: 4,
          tension: 0.25,
          spanGaps: true,
          fill: false,
        };
      });

    const [decisionsChart, returnedChart] = this.reviewerCharts;
    decisionsChart.data.datasets = lineDatasets("total");
    returnedChart.data.datasets = lineDatasets("returned");
    this.reviewerCharts.forEach((c) => c.update());

    this.renderReviewerTotals(selected, reviewers);
  }

  renderReviewerTotals(selected, allReviewers) {
    const el = this.reviewerTotalsTarget;
    el.innerHTML = "";
    if (selected.length === 0) return;

    selected.forEach((r) => {
      const i = allReviewers.indexOf(r);
      const color = PALETTE[i % PALETTE.length];
      const approved = r.data.reduce((s, d) => s + d.approved, 0);
      const returned = r.data.reduce((s, d) => s + d.returned, 0);
      const total = approved + returned;
      const rate = total > 0 ? ((returned / total) * 100).toFixed(1) : "—";

      const row = document.createElement("div");
      row.className = "ship-monitor__reviewer-total";

      const mkSpan = (cls, text) => {
        const s = document.createElement("span");
        s.className = cls;
        s.textContent = text;
        return s;
      };

      const name = mkSpan("ship-monitor__reviewer-total-name", r.name);
      name.style.color = color;
      const sep = () => mkSpan("ship-monitor__reviewer-total-sep", "·");

      row.append(
        name,
        mkSpan(
          "ship-monitor__reviewer-total-stat",
          `${approved.toLocaleString()} approved`,
        ),
        sep(),
        mkSpan(
          "ship-monitor__reviewer-total-stat",
          `${returned.toLocaleString()} returned`,
        ),
        sep(),
        mkSpan("ship-monitor__reviewer-total-rate", `${rate}% rejection`),
      );
      el.appendChild(row);
    });
  }

  disconnect() {
    this.charts.forEach((c) => c.destroy());
    if (this.closeDropdownFn)
      document.removeEventListener("click", this.closeDropdownFn);
  }
}
