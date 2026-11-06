import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = [
    "countdown",
    "message",
    "platform",
    "metric",
    "threshold",
    "preview",
  ];
  static values = {
    deadline: String,
    serverTime: String,
    statusUrl: String,
    thresholds: Object,
  };

  connect() {
    if (this.hasPlatformTarget) this.platformChanged();
    if (!this.hasDeadlineValue) return;
    this.offset = Date.parse(this.serverTimeValue) - Date.now();
    this.tick();
    this.clock = setInterval(() => this.tick(), 250);
    this.poller = setInterval(() => this.poll(), 3000);
  }

  disconnect() {
    clearInterval(this.clock);
    clearInterval(this.poller);
    this.request?.abort();
  }

  tick() {
    const seconds = Math.max(
      0,
      Math.ceil(
        (Date.parse(this.deadlineValue) - Date.now() - this.offset) / 1000,
      ),
    );
    this.countdownTarget.textContent =
      seconds > 0 ? `${seconds}s` : "Waiting for processing";
  }

  async poll() {
    if (this.request) return;
    this.request = new AbortController();
    try {
      const response = await fetch(this.statusUrlValue, {
        headers: { Accept: "application/json" },
        signal: this.request.signal,
      });
      if (!response.ok) throw new Error("Unable to check status");
      const result = await response.json();
      this.offset = Date.parse(result.server_time) - Date.now();
      if (result.status !== "scheduled") Turbo.visit(result.destination);
      else
        this.messageTarget.textContent =
          "Nothing changes until this decision processes.";
    } catch (error) {
      if (error.name !== "AbortError")
        this.messageTarget.textContent =
          "Status unavailable. Refresh to check whether this decision processed.";
    } finally {
      this.request = null;
    }
  }

  platformChanged() {
    const previous = this.metricTarget.value;
    const metrics = Object.keys(
      this.thresholdsValue[this.platformTarget.value] || {},
    );
    this.metricTarget.replaceChildren(
      new Option("Choose metric", ""),
      ...metrics.map((metric) => new Option(metric, metric)),
    );
    this.metricTarget.value = metrics.includes(previous)
      ? previous
      : metrics[0] || "";
    this.thresholdChanged();
  }

  thresholdChanged() {
    const thresholds =
      this.thresholdsValue[this.platformTarget.value]?.[
        this.metricTarget.value
      ];
    this.thresholdTarget.textContent = thresholds
      ? `Good: ${thresholds[0] ?? "manual review"} · Great: ${thresholds[1] ?? "manual review"}`
      : "Choose a platform and metric, or explain a manual exception.";
  }

  tierChanged(event) {
    this.previewTargets.forEach((preview) => {
      preview.hidden = preview.dataset.tier !== event.target.value;
    });
  }
}
