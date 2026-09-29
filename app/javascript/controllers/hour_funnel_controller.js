import { Controller } from "@hotwired/stimulus";
import { select } from "d3";
import { sankey, sankeyLeft, sankeyLinkHorizontal } from "d3-sankey";

// Draws the hour funnel as a Sankey in either unit. Nodes and links arrive
// with both units on them; switching unit re-filters and redraws rather than
// asking the server again. Partial-loss nodes carry no ship value, so in the
// ships unit they and their links fall out of the graph on their own.
export default class extends Controller {
  static targets = ["chart", "tooltip", "unitButton"];
  static values = {
    nodes: Array,
    links: Array,
    unit: { type: String, default: "hours" },
  };

  static NODE_WIDTH = 14;
  // Two label lines need about 26px, and the smallest leaks are only a pixel
  // tall, so the padding is what keeps neighbouring labels apart.
  static NODE_PADDING = 28;
  static HEIGHT = 640;
  // Seven columns of labelled nodes need room; below this the chart scrolls
  // sideways rather than letting labels pile onto the next column.
  static MIN_WIDTH = 1100;
  // Every label sits to the right of its node, clear of the flows coming in,
  // so the last column needs this much room reserved past its nodes.
  static LABEL_ROOM = 200;

  connect() {
    this.resize = () => this.render();
    window.addEventListener("resize", this.resize);
    this.render();
  }

  disconnect() {
    window.removeEventListener("resize", this.resize);
  }

  setUnit(event) {
    this.unitValue = event.params.unit;
  }

  unitValueChanged() {
    this.unitButtonTargets.forEach((button) => {
      button.classList.toggle(
        "is-active",
        button.dataset.hourFunnelUnitParam === this.unitValue,
      );
    });
    if (this.hasChartTarget) this.render();
  }

  render() {
    const unit = this.unitValue;
    const links = this.linksValue
      .filter((link) => (link[unit] ?? 0) > 0)
      .map((link) => ({ ...link, value: link[unit] }));
    const used = new Set(links.flatMap((link) => [link.source, link.target]));
    const nodes = this.nodesValue
      .filter((node) => used.has(node.key))
      .map((node) => ({ ...node }));

    const width = Math.max(
      this.chartTarget.clientWidth,
      this.constructor.MIN_WIDTH,
    );
    const height = this.constructor.HEIGHT;
    const layout = sankey()
      .nodeId((node) => node.key)
      .nodeAlign(sankeyLeft)
      .nodeSort(null)
      .linkSort(null)
      .nodeWidth(this.constructor.NODE_WIDTH)
      .nodePadding(this.constructor.NODE_PADDING)
      .extent([
        [1, 8],
        [width - this.constructor.LABEL_ROOM, height - 8],
      ]);
    const graph = layout({ nodes, links });
    const total = graph.nodes.length ? graph.nodes[0].value : 0;

    this.chartTarget.replaceChildren();
    const svg = select(this.chartTarget)
      .append("svg")
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("width", width)
      .attr("height", height);

    svg
      .append("g")
      .attr("fill", "none")
      .selectAll("path")
      .data(graph.links)
      .join("path")
      .attr("class", "hour-funnel__sankey-link")
      .attr("d", sankeyLinkHorizontal())
      .attr("stroke", (link) => this.color(link.target.kind))
      .attr("stroke-width", (link) => Math.max(1, link.width))
      .on("mousemove", (event, link) =>
        this.showTooltip(
          event,
          `${link.source.label} → ${link.target.label}`,
          this.format(link.value, unit),
        ),
      )
      .on("mouseleave", () => this.hideTooltip());

    const node = svg
      .append("g")
      .selectAll("g")
      .data(graph.nodes)
      .join("g")
      .on("mousemove", (event, item) =>
        this.showTooltip(
          event,
          item.label,
          `${this.format(item.value, unit)}${this.share(item.value, total)}`,
        ),
      )
      .on("mouseleave", () => this.hideTooltip());

    node
      .append("rect")
      .attr("class", "hour-funnel__sankey-node")
      .attr("x", (item) => item.x0)
      .attr("y", (item) => item.y0)
      .attr("width", (item) => item.x1 - item.x0)
      .attr("height", (item) => Math.max(1, item.y1 - item.y0))
      .attr("fill", (item) => this.color(item.kind));

    const label = node
      .append("text")
      .attr("class", "hour-funnel__sankey-label")
      .attr("x", (item) => item.x1 + 6)
      .attr("y", (item) => (item.y0 + item.y1) / 2);
    label
      .append("tspan")
      .attr("dy", "-0.2em")
      .text((item) => item.label);
    label
      .append("tspan")
      .attr("class", "hour-funnel__sankey-value")
      .attr("x", (item) => item.x1 + 6)
      .attr("dy", "1.1em")
      .text((item) => this.format(item.value, unit));
  }

  showTooltip(event, title, value) {
    const bounds = this.chartTarget.getBoundingClientRect();
    this.tooltipTarget.textContent = `${title}: ${value}`;
    this.tooltipTarget.hidden = false;
    this.tooltipTarget.style.left = `${event.clientX - bounds.left + 12}px`;
    this.tooltipTarget.style.top = `${event.clientY - bounds.top + 12}px`;
  }

  hideTooltip() {
    this.tooltipTarget.hidden = true;
  }

  format(value, unit) {
    if (unit === "ships") {
      return `${value.toLocaleString()} ${value === 1 ? "ship" : "ships"}`;
    }
    return `${value.toLocaleString(undefined, { maximumFractionDigits: 1 })}h`;
  }

  share(value, total) {
    if (!total) return "";
    return ` (${((value * 100) / total).toFixed(1)}% of ${this.unitValue === "ships" ? "shipped" : "devlogged"})`;
  }

  color(kind) {
    const token = {
      kept: "--color-brand-mint",
      held: "--color-brand-yellow",
      lost: "--color-brand-salmon",
    }[kind];
    return getComputedStyle(document.documentElement)
      .getPropertyValue(token)
      .trim();
  }
}
