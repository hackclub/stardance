import { Controller } from "@hotwired/stimulus";
import { groups, select, sum } from "d3";
import { sankey, sankeyLeft, sankeyLinkHorizontal } from "d3-sankey";

export default class extends Controller {
  static targets = ["chart", "typeButton", "unitButton", "unshippedToggle"];
  static values = {
    links: Array,
    unshippedLinks: Array,
    unshipped: { type: Boolean, default: false },
    type: { type: String, default: "both" },
    unit: { type: String, default: "hours" },
  };

  static MIN_COLUMN = 175;
  static HEIGHT = 900;
  static LABEL_ROOM = 190;

  static KIND = {
    Devlogged: "path",
    Shipped: "path",
    "Shipwrights review": "path",
    "Build review": "path",
    "Reship, skipped review": "path",
    "GOI review": "path",
    "Fraud check": "path",
    "Hardware, skipped": "path",
    Airtable: "path",
    Unified: "path",
    Fraud: "rejected",
    "Rejected by ship review": "rejected",
    "Rejected by GOI": "rejected",
    "Duplicate in Unified": "rejected",
    "Rejected by sync": "rejected",
    "Waiting on Shipwrights": "team",
    "Waiting on build review": "team",
    "Waiting on GOI": "team",
    "Waiting on fraud team": "team",
    "Waiting on final pass": "team",
    "Final-pass error, fixable": "team",
    "Approved, no GOI review": "bug",
    "Returned, <30d ago": "builder",
    "Returned, >30d ago": "builder",
    "Misfiled, back to design": "builder",
    "Deflated by GOI": "deflated",
    "Deducted by fraud team": "deflated",
    "Whole-minute rounding": "deflated",
    "Not reviewed by GOI": "bug",
    "Lost to key collision": "bug",
    "Cut off by a later ship": "bug",
    "Cleared, never synced": "bug",
    "Not shipped yet": "builder",
    "Devlog deleted": "rejected",
    "Fraud before shipping": "rejected",
    "Design phase (hardware)": "deflated",
  };

  static LEGEND = [
    ["path", "Reached Unified"],
    ["rejected", "Rejected, fraud included"],
    ["team", "Waiting on a team"],
    ["builder", "Waiting on the builder"],
    ["deflated", "Deflated"],
    ["bug", "Lost to a bug"],
  ];

  static ORDER = [
    "Devlogged",
    "Shipped",
    "Not shipped yet",
    "Design phase (hardware)",
    "Devlog deleted",
    "Fraud before shipping",
    "Reship, skipped review",
    "Shipwrights review",
    "Build review",
    "Fraud",
    "GOI review",
    "Waiting on Shipwrights",
    "Waiting on build review",
    "Returned, <30d ago",
    "Returned, >30d ago",
    "Cut off by a later ship",
    "Misfiled, back to design",
    "Rejected by ship review",
    "Fraud check",
    "Hardware, skipped",
    "Deflated by GOI",
    "Waiting on GOI",
    "Rejected by GOI",
    "Approved, no GOI review",
    "Whole-minute rounding",
    "Not reviewed by GOI",
    "Airtable",
    "Deducted by fraud team",
    "Waiting on fraud team",
    "Unified",
    "Waiting on final pass",
    "Final-pass error, fixable",
    "Lost to key collision",
    "Duplicate in Unified",
    "Rejected by sync",
    "Cleared, never synced",
  ];

  static COLUMN = {
    Devlogged: "Devlogged",
    Shipped: "Shipped",
    "Shipwrights review": "Shipwrights",
    "Build review": "Build review",
    "GOI review": "GOI review",
    "Fraud check": "Fraud check",
    "Hardware, skipped": "Fraud check (skipped)",
    Airtable: "Airtable",
    Unified: "Final pass",
  };

  connect() {
    this.resize = () => this.render();
    window.addEventListener("resize", this.resize);
    this.render();
  }

  disconnect() {
    window.removeEventListener("resize", this.resize);
  }

  toggleUnshipped(event) {
    this.unshippedValue = event.target.checked;
  }

  unshippedValueChanged() {
    if (this.hasChartTarget) this.render();
  }

  setType(event) {
    this.typeValue = event.params.type;
  }

  setUnit(event) {
    this.unitValue = event.params.unit;
  }

  typeValueChanged() {
    this.markActive(
      this.typeButtonTargets,
      "shipFunnelTypeParam",
      this.typeValue,
    );
    if (this.hasChartTarget) this.render();
  }

  unitValueChanged() {
    this.markActive(
      this.unitButtonTargets,
      "shipFunnelUnitParam",
      this.unitValue,
    );
    if (this.hasChartTarget) this.render();
  }

  markActive(buttons, param, value) {
    buttons.forEach((button) => {
      const active = button.dataset[param] === value;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });
  }

  linksForView() {
    const unit = this.unitValue;
    const totals = new Map();
    const unshipped =
      this.unshippedValue && unit === "hours" ? this.unshippedLinksValue : [];
    for (const link of [...unshipped, ...this.linksValue]) {
      if (this.typeValue !== "both" && link.kind !== this.typeValue) continue;
      const value = link[unit];
      if (!(value > 0)) continue;
      const key = `${link.source}\u0000${link.target}`;
      totals.set(key, (totals.get(key) || 0) + value);
    }
    return [...totals].map(([key, value]) => {
      const [source, target] = key.split("\u0000");
      return { source, target, value };
    });
  }

  format(value) {
    if (this.unitValue === "ships")
      return `${Math.round(value).toLocaleString()} ships`;
    return value >= 1000
      ? `${(value / 1000).toFixed(1)}k h`
      : `${Math.round(value)} h`;
  }

  render() {
    const { MIN_COLUMN, HEIGHT, LABEL_ROOM, KIND, LEGEND, ORDER, COLUMN } =
      this.constructor;
    const links = this.linksForView();
    const targets = new Set(links.map((link) => link.target));
    const total = sum(
      links.filter((link) => !targets.has(link.source)),
      (link) => link.value,
    );
    const percent = (value) => `${((100 * value) / (total || 1)).toFixed(1)}%`;
    const kindOf = (name) => KIND[name] || "bug";
    const order = (name) =>
      ORDER.includes(name) ? ORDER.indexOf(name) : ORDER.length;
    const unitLabel = this.unitValue === "hours" ? " h" : " ships";

    const svg = select(this.chartTarget);
    svg.selectAll("*").remove();
    if (!links.length) return;

    const depth = new Map();
    const deepest = (name) => {
      if (!depth.has(name)) {
        depth.set(name, 0);
        const into = links.filter((link) => link.target === name);
        depth.set(
          name,
          into.length
            ? Math.max(...into.map((link) => deepest(link.source) + 1))
            : 0,
        );
      }
      return depth.get(name);
    };
    const columnCount =
      Math.max(...links.map((link) => deepest(link.target))) + 1;
    const WIDTH = Math.max(
      this.chartTarget.parentElement.clientWidth,
      (columnCount - 1) * MIN_COLUMN + LABEL_ROOM + 14,
    );
    svg
      .attr("width", WIDTH)
      .attr("height", HEIGHT)
      .attr("viewBox", `0 0 ${WIDTH} ${HEIGHT}`);

    const names = [
      ...new Set(links.flatMap((link) => [link.source, link.target])),
    ];
    const TOP = 40;
    const layout = sankey()
      .nodeId((node) => node.name)
      .nodeAlign(sankeyLeft)
      .nodeWidth(12)
      .nodePadding(30)
      .nodeSort((a, b) => order(a.name) - order(b.name))
      .linkSort(
        (a, b) =>
          order(a.target.name) - order(b.target.name) ||
          order(a.source.name) - order(b.source.name),
      )
      .extent([
        [2, TOP],
        [WIDTH - LABEL_ROOM, HEIGHT - 40],
      ]);
    const graph = layout({
      nodes: names.map((name) => ({ name })),
      links: links.map((link) => ({ ...link })),
    });

    const sources = new Set(links.map((link) => link.source));
    const ends = {};
    for (const link of links) {
      if (!sources.has(link.target))
        ends[kindOf(link.target)] =
          (ends[kindOf(link.target)] || 0) + link.value;
    }

    const columns = groups(graph.nodes, (node) => node.depth).map(
      ([, nodes]) => {
        const labels = [
          ...new Set(nodes.map((node) => COLUMN[node.name]).filter(Boolean)),
        ];
        const shown = labels.filter(
          (label) =>
            !(
              label === "Fraud check (skipped)" &&
              labels.includes("Fraud check")
            ),
        );
        const bothReviews =
          shown.includes("Shipwrights") && shown.includes("Build review");
        return {
          x: nodes[0].x0,
          label: bothReviews ? "Ship review" : shown.join(" / "),
        };
      },
    );
    svg
      .append("g")
      .selectAll("text")
      .data(columns)
      .join("text")
      .attr("class", "ship-funnel__column-label")
      .attr("x", (column) => column.x)
      .attr("y", 18)
      .text((column) => column.label);

    svg
      .append("g")
      .selectAll("path")
      .data(graph.links)
      .join("path")
      .attr(
        "class",
        (link) =>
          `ship-funnel__link ship-funnel__link--${kindOf(link.target.name)}`,
      )
      .attr("d", sankeyLinkHorizontal())
      .attr("stroke-width", (link) => Math.max(1, link.width))
      .append("title")
      .text(
        (link) =>
          `${link.source.name} → ${link.target.name}: ${Math.round(link.value).toLocaleString()}${unitLabel} (${percent(link.value)})`,
      );

    const node = svg.append("g").selectAll("g").data(graph.nodes).join("g");
    node
      .append("rect")
      .attr(
        "class",
        (d) => `ship-funnel__node ship-funnel__node--${kindOf(d.name)}`,
      )
      .attr("x", (d) => d.x0)
      .attr("y", (d) => d.y0)
      .attr("width", (d) => d.x1 - d.x0)
      .attr("height", (d) => Math.max(2, d.y1 - d.y0))
      .attr("rx", 2)
      .append("title")
      .text(
        (d) =>
          `${d.name}: ${Math.round(d.value).toLocaleString()}${unitLabel} (${percent(d.value)})`,
      );

    const label = node
      .append("text")
      .attr(
        "class",
        (d) =>
          `ship-funnel__label${kindOf(d.name) === "path" ? " ship-funnel__label--stage" : ""}`,
      )
      .attr("x", (d) => d.x1 + 8)
      .attr("y", (d) => (d.y0 + d.y1) / 2 - 8);
    label
      .append("tspan")
      .attr("class", "ship-funnel__label-name")
      .attr("dy", "0.35em")
      .text((d) => d.name);
    label
      .append("tspan")
      .attr("class", "ship-funnel__label-value")
      .attr("x", (d) => d.x1 + 8)
      .attr("dy", "1.3em")
      .text((d) => `${this.format(d.value)} · ${percent(d.value)}`);

    const shown = LEGEND.filter(([kind]) => ends[kind]);
    const legend = svg
      .append("g")
      .attr("class", "ship-funnel__legend")
      .attr(
        "transform",
        `translate(${WIDTH - 270},${HEIGHT - 12 - shown.length * 21})`,
      );
    const row = legend
      .selectAll("g")
      .data(shown)
      .join("g")
      .attr("transform", (_, index) => `translate(0,${index * 21})`);
    row
      .append("rect")
      .attr("class", ([kind]) => `ship-funnel__node ship-funnel__node--${kind}`)
      .attr("width", 11)
      .attr("height", 11)
      .attr("y", -9)
      .attr("rx", 2.5);
    const legendText = row
      .append("text")
      .attr("class", "ship-funnel__label")
      .attr("x", 19);
    legendText
      .append("tspan")
      .attr("class", "ship-funnel__label-name")
      .text(([, name]) => `${name}  `);
    legendText
      .append("tspan")
      .attr("class", "ship-funnel__label-value")
      .text(([kind]) => `${this.format(ends[kind])} · ${percent(ends[kind])}`);
  }
}
