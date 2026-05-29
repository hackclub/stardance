import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

// GitHub-style contribution calendar using D3
// Displays contribution data in a compact grid format (similar to GitHub's contribution graph)
// Data is prepared server-side with levels already calculated
export default class extends Controller {
  static values = {
    days: Array, // Array of {date: "YYYY-MM-DD", count: number, level: number, day_of_week: number, week_index: number}
  };

  connect() {
    if (this.hasDaysValue && this.daysValue.length > 0) {
      this.renderCalendar();
    }
  }

  renderCalendar() {
    const days = this.daysValue;

    // Clear any existing content
    this.element.innerHTML = "";

    // Configuration - compact size (2x the 1/4 size = 1/2 of original, then +30%)
    const cellSize = 6.5; // Size of each day square (5 * 1.3)
    const cellSpacing = 1.95; // Space between squares (1.5 * 1.3)
    const weekLabelWidth = 0; // No day labels
    const monthLabelHeight = 15.6; // Space for month labels at top (12 * 1.3)

    // Calculate number of weeks
    const numWeeks = Math.max(...days.map((d) => d.week_index)) + 1;

    // Calculate dimensions
    const width = weekLabelWidth + numWeeks * (cellSize + cellSpacing);
    const height = monthLabelHeight + 7 * (cellSize + cellSpacing);

    // Create SVG
    const svg = d3
      .create("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", [0, 0, width, height])
      .attr("style", "max-width: 100%; height: auto;");

    // Calculate month positions
    const months = this.getMonthPositions(
      days,
      cellSize,
      cellSpacing,
      weekLabelWidth,
    );

    // Add month labels (smaller font for compact view)
    svg
      .append("g")
      .selectAll("text")
      .data(months)
      .join("text")
      .attr("x", (d) => d.x)
      .attr("y", 11)
      .attr("fill", "rgba(255, 255, 255, 0.5)")
      .attr("font-size", "10px")
      .attr("font-family", "var(--font-family-sans)")
      .text((d) => d.label);

    // Create tooltip
    const tooltip = d3
      .select("body")
      .append("div")
      .attr("class", "github-calendar-tooltip")
      .style("position", "absolute")
      .style("visibility", "hidden")
      .style("background-color", "rgba(0, 0, 0, 0.9)")
      .style("color", "white")
      .style("padding", "6px 10px")
      .style("border-radius", "4px")
      .style("font-size", "12px")
      .style("font-family", "var(--font-family-sans)")
      .style("pointer-events", "none")
      .style("z-index", "10000")
      .style("white-space", "nowrap");

    // Add contribution squares
    svg
      .append("g")
      .selectAll("rect")
      .data(days.filter((d) => !d.future)) // Don't render future dates
      .join("rect")
      .attr(
        "x",
        (d) => weekLabelWidth + d.week_index * (cellSize + cellSpacing),
      )
      .attr(
        "y",
        (d) => monthLabelHeight + d.day_of_week * (cellSize + cellSpacing),
      )
      .attr("width", cellSize)
      .attr("height", cellSize)
      .attr("rx", 1.3)
      .attr("fill", (d) => this.getLevelColor(d.level))
      .attr("stroke", "none")
      .style("cursor", "pointer")
      .on("mouseenter", function (event, d) {
        d3.select(this)
          .attr("stroke", "rgba(255, 255, 255, 0.5)")
          .attr("stroke-width", 1);

        const date = new Date(d.date);
        const dateFormatted = date.toLocaleDateString("en-US", {
          month: "short",
          day: "numeric",
          year: "numeric",
        });
        const contributionText =
          d.count === 1 ? "contribution" : "contributions";

        tooltip
          .style("visibility", "visible")
          .text(`${d.count} ${contributionText} - ${dateFormatted}`);
      })
      .on("mousemove", function (event) {
        tooltip
          .style("top", event.pageY - 60 + "px")
          .style("left", event.pageX - tooltip.node().offsetWidth / 2 + "px");
      })
      .on("mouseleave", function () {
        d3.select(this).attr("stroke", "none");
        tooltip.style("visibility", "hidden");
      });

    // Append SVG to element
    this.element.appendChild(svg.node());
  }

  // Get color for each level (purple theme)
  getLevelColor(level) {
    const colors = {
      0: "#161b22", // No contributions (dark gray)
      1: "#400554", // Level 1 (dark purple)
      2: "#693699", // Level 2 (medium purple)
      3: "#7c40a9", // Level 3 (purple)
      4: "#9570dd", // Level 4 (light purple)
      5: "#b794ff", // Level 5 (lighter purple - 30+ contributions)
    };
    return colors[level] || colors[0];
  }

  // Calculate month label positions based on the first Sunday of each month
  getMonthPositions(days, cellSize, cellSpacing, weekLabelWidth) {
    const monthPositions = [];
    let lastMonth = -1;
    let isFirstMonth = true;

    days.forEach((day) => {
      const date = new Date(day.date);
      const month = date.getMonth();

      // Add label only at the start of a new month and at the beginning of a week (Sunday)
      // Skip the very first month to avoid duplicate
      if (month !== lastMonth && day.day_of_week === 0) {
        if (!isFirstMonth) {
          const monthLabel = date.toLocaleDateString("en-US", {
            month: "short",
          });
          monthPositions.push({
            x: weekLabelWidth + day.week_index * (cellSize + cellSpacing),
            label: monthLabel,
          });
        }
        lastMonth = month;
        isFirstMonth = false;
      }
    });

    return monthPositions;
  }

  disconnect() {
    // Clean up tooltip if it exists
    d3.selectAll(".github-calendar-tooltip").remove();
  }
}
