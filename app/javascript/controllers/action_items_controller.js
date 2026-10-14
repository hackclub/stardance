import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox", "error", "progress", "submit", "block", "hint"];

  connect() {
    this.report();
  }

  report() {
    if (this.hasProgressTarget) {
      const total = this.checkboxTargets.length;
      this.progressTarget.textContent = `${this.tickedCount} of ${total} confirmed`;
    }

    this.syncReadyState();
    this.syncSubmit();
    if (this.allTicked) this.clearError();
  }

  syncReadyState() {
    if (this.hasBlockTarget) {
      this.blockTarget.classList.toggle("action-items--ready", this.allTicked);
    }

    if (this.hasHintTarget) {
      const { ready, pending } = this.hintTarget.dataset;
      this.hintTarget.textContent = this.allTicked ? ready : pending;
    }
  }

  syncSubmit() {
    if (!this.hasSubmitTarget) return;

    const form = this.element.closest("form") || this.element;
    if (
      form.dataset.tierMaxes &&
      typeof window.fundingValidate === "function"
    ) {
      window.fundingValidate(form);
      return;
    }

    this.submitTarget.disabled = !this.allTicked;
  }

  guard(event) {
    if (this.allTicked) return;

    event.preventDefault();

    if (this.hasErrorTarget) {
      this.errorTarget.textContent =
        "Confirm each change your reviewer asked for before submitting again.";
      this.errorTarget.hidden = false;
    }

    const pending = this.checkboxTargets.find((box) => !box.checked);
    if (pending) pending.focus();
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true;
  }

  get tickedCount() {
    return this.checkboxTargets.filter((box) => box.checked).length;
  }

  get allTicked() {
    return this.checkboxTargets.every((box) => box.checked);
  }
}
