import { Controller } from "@hotwired/stimulus";

const TIERS = ["good", "great"];

export default class extends Controller {
  static targets = ["group", "summary", "preview", "note", "submit"];
  static values = { thresholds: Object, currentTier: String };

  connect() {
    this.groupTargets.forEach((group) => {
      if (this.field(group, "platform")) this.fillMetrics(group);
      this.showVerdict(group, false);
    });
    this.refresh();
  }

  platformChanged(event) {
    const group = this.groupOf(event.target);
    this.fillMetrics(group);
    this.showVerdict(group, true);
    this.refresh();
  }

  evidenceChanged(event) {
    this.showVerdict(this.groupOf(event.target), true);
    this.refresh();
  }

  selectOpen() {
    this.checkboxes.forEach((box) => (box.checked = true));
    this.refresh();
  }

  selectNone() {
    this.checkboxes.forEach((box) => (box.checked = false));
    this.refresh();
  }

  checkAll() {
    const boxes = this.element.querySelectorAll('[data-role="check"]');
    const checked = [...boxes].some((box) => !box.checked);
    boxes.forEach((box) => (box.checked = checked));
  }

  useReply({ params: { text } }) {
    const group = this.selectedGroups[0];
    const good = group && this.thresholdsFor(group)?.[0];
    const threshold = good
      ? `${this.field(group, "platform").value} threshold yet (${good.toLocaleString()} ${this.field(group, "metric").value} for Good)`
      : "threshold yet";
    this.noteTarget.value = text.replace("%{threshold}", threshold);
    this.noteTarget.focus();
  }

  refresh() {
    const selected = this.checkboxes.filter((box) => box.checked).length;
    this.summaryTarget.textContent = this.checkboxes.length
      ? `${selected} of ${this.checkboxes.length} open ${this.checkboxes.length === 1 ? "mention" : "mentions"} selected`
      : "Nothing open to review";
    this.submitTargets.forEach((button) => {
      if (selected === 0) button.disabled = true;
      else if (!button.hasAttribute("data-blocked")) button.disabled = false;
    });
    this.groupTargets.forEach((group) =>
      group.classList.toggle(
        "virality-review__group--selected",
        this.selectedGroups.includes(group),
      ),
    );
    this.showPreview();
  }

  showPreview() {
    const tiers = this.selectedGroups
      .map((group) => this.field(group, "tier")?.value)
      .concat(this.currentTierValue);
    const tier = [...TIERS].reverse().find((name) => tiers.includes(name));
    this.previewTargets.forEach((preview) => {
      preview.hidden = preview.dataset.tier !== tier;
    });
  }

  fillMetrics(group) {
    const metric = this.field(group, "metric");
    const previous = metric.value;
    const metrics = Object.keys(
      this.thresholdsValue[this.field(group, "platform").value] || {},
    );
    metric.replaceChildren(
      new Option("Choose metric", ""),
      ...metrics.map((name) => new Option(name, name)),
    );
    metric.value = metrics.includes(previous) ? previous : metrics[0] || "";
  }

  showVerdict(group, pickTier) {
    const verdict = group.querySelector('[data-role="verdict"]');
    if (!verdict) return;
    const thresholds = this.thresholdsFor(group);
    if (!thresholds) {
      verdict.textContent =
        "Choose a platform and metric, or explain a manual exception.";
      return;
    }
    const [good, great] = thresholds;
    const format = (value) => value?.toLocaleString() ?? "manual review";
    let text = `Good: ${format(good)} · Great: ${format(great)}`;
    const count = this.field(group, "count");
    if (count.value !== "") {
      const value = Number(count.value);
      const tier =
        great != null && value >= great
          ? "great"
          : good != null && value >= good
            ? "good"
            : null;
      text += tier ? ` · meets ${tier}` : " · below threshold";
      if (tier && pickTier) this.field(group, "tier").value = tier;
    }
    verdict.textContent = text;
  }

  thresholdsFor(group) {
    const platform = this.field(group, "platform")?.value;
    const metric = this.field(group, "metric")?.value;
    return this.thresholdsValue[platform]?.[metric];
  }

  field(group, role) {
    return group.querySelector(`[data-role="${role}"]`);
  }

  groupOf(element) {
    return element.closest('[data-virality-batch-target="group"]');
  }

  get checkboxes() {
    return [...this.element.querySelectorAll('[data-role="select"]')];
  }

  get selectedGroups() {
    return this.groupTargets.filter((group) =>
      group.querySelector('[data-role="select"]:checked'),
    );
  }
}
