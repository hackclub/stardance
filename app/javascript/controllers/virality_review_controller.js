import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = [
    "countdown",
    "message",
    "platform",
    "metric",
    "count",
    "threshold",
    "tier",
    "preview",
    "check",
    "note",
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
    if (this.hasStatusUrlValue)
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

  platformChanged(event) {
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
    this.thresholdChanged(event);
  }

  // Shows the thresholds for the chosen metric and, when the reviewer edits
  // the evidence, picks the highest tier the count reaches.
  thresholdChanged(event) {
    const thresholds = this.currentThresholds;
    if (!thresholds) {
      this.thresholdTarget.textContent =
        "Choose a platform and metric, or explain a manual exception.";
      return;
    }
    const [good, great] = thresholds;
    const format = (value) => value?.toLocaleString() ?? "manual review";
    let text = `Good: ${format(good)} · Great: ${format(great)}`;
    if (this.countTarget.value !== "") {
      const count = Number(this.countTarget.value);
      const tier =
        great != null && count >= great
          ? "great"
          : good != null && count >= good
            ? "good"
            : null;
      text += tier ? ` · meets ${tier}` : " · below threshold";
      if (tier && event) this.selectTier(tier);
    }
    this.thresholdTarget.textContent = text;
  }

  tierChanged(event) {
    this.showPreview(event.target.value);
  }

  selectTier(tier) {
    this.tierTargets.forEach((radio) => {
      radio.checked = radio.value === tier;
    });
    this.showPreview(tier);
  }

  showPreview(tier) {
    this.previewTargets.forEach((preview) => {
      preview.hidden = preview.dataset.tier !== tier;
    });
  }

  checkAll() {
    const checked = this.checkTargets.some((box) => !box.checked);
    this.checkTargets.forEach((box) => {
      box.checked = checked;
    });
  }

  // Fills the review note with a canned reply. "%{threshold}" becomes the
  // Good threshold for the chosen platform and metric.
  useReply({ params: { text } }) {
    const good = this.currentThresholds?.[0];
    const threshold = good
      ? `${this.platformTarget.value} threshold yet (${good.toLocaleString()} ${this.metricTarget.value} for Good)`
      : "threshold yet";
    this.noteTarget.value = text.replace("%{threshold}", threshold);
    this.noteTarget.focus();
  }

  get currentThresholds() {
    return this.thresholdsValue[this.platformTarget.value]?.[
      this.metricTarget.value
    ];
  }
}
