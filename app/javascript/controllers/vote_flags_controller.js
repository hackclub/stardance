import { Controller } from "@hotwired/stimulus";

// Payout review flagging: "Flag selected" stays disabled until every ticked
// reason has a long enough explanation. The server enforces the same rules.
export default class extends Controller {
  static targets = ["flag", "summary", "submit"];
  static values = { minLength: Number, maxLength: Number };

  connect() {
    this.update();
  }

  update() {
    if (!this.hasSubmitTarget) return;

    this.flagTargets.forEach((flag) => this.refreshHint(flag));

    const selected = this.flagTargets.filter(
      (flag) => this.checkboxFor(flag).checked,
    );
    const ready = selected.filter((flag) => this.isReady(this.reasonFor(flag)));

    this.submitTarget.disabled =
      selected.length === 0 || ready.length !== selected.length;
    this.summaryTarget.textContent = this.summaryFor(
      selected.length,
      ready.length,
    );
  }

  refreshHint(flag) {
    const reason = this.reasonFor(flag);
    const hint = flag.querySelector("[data-vote-flags-hint]");
    const length = reason.value.length;

    hint.textContent = `${length} / ${this.maxLengthValue} · at least ${this.minLengthValue}`;
    hint.classList.toggle(
      "payout-review-modal__flag-hint--short",
      length > 0 && !this.isReady(reason),
    );
  }

  isReady(reason) {
    return reason.value.trim().length >= this.minLengthValue;
  }

  summaryFor(selectedCount, readyCount) {
    if (selectedCount === 0) return "Select ratings to flag";
    if (readyCount !== selectedCount)
      return `${selectedCount} selected · add a reason to each`;

    return `${selectedCount} selected`;
  }

  checkboxFor(flag) {
    return flag.querySelector('input[type="checkbox"]');
  }

  reasonFor(flag) {
    return flag.querySelector("textarea");
  }
}
