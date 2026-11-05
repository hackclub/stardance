import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["field", "form", "preview", "previewButton"];

  disconnect() {
    clearTimeout(this.timer);
  }

  clear() {
    clearTimeout(this.timer);
    this.previewTarget.textContent = "No changes selected.";
    this.previewButtonTarget.hidden = true;
    this.fieldTargets.forEach((field) => (field.disabled = false));
  }

  reset() {
    this.clear();
    if (
      !this.fieldTargets.some(
        (field) =>
          field.type === "radio" && field.checked && !field.defaultChecked,
      )
    )
      return;

    this.previewTarget.textContent = "Calculating payout changes…";
    this.timer = setTimeout(() => this.formTarget.requestSubmit(), 300);
  }

  start() {
    this.previewTarget.textContent = "Calculating payout changes…";
    this.previewButtonTarget.hidden = true;
    // Keep the visible selection equal to the signed preview while it loads.
    // Turbo has already collected the form data before submit-start fires.
    this.fieldTargets.forEach((field) => (field.disabled = true));
  }

  finish({ detail }) {
    if (!detail.fetchResponse) this.failed();
  }

  loaded() {
    this.fieldTargets.forEach((field) => (field.disabled = false));
    this.previewButtonTarget.hidden =
      !this.previewTarget.querySelector("[role=alert]");
  }

  failed(event) {
    event?.preventDefault();
    this.clear();
    this.previewButtonTarget.hidden = false;
    this.previewTarget.textContent =
      "Couldn’t calculate the changes. Try again.";
  }
}
