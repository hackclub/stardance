import { Controller } from "@hotwired/stimulus";

// Guards the verdict form on the reviewer's screenshot judgement. Marking the
// ship event screenshot as not showing the project surfaces a soft warning, and
// pairing that with an Approve verdict disables the submit button (with a submit
// guard as a safety net) — an incorrect screenshot can't be approved.
export default class extends Controller {
  static targets = ["warning", "submit"];

  connect() {
    this.toggle();
  }

  toggle() {
    const incorrect = this.screenshotValue === "no";
    this.warningTarget.hidden = !incorrect;
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled =
        incorrect && this.verdictValue === "approved";
    }
  }

  guardSubmit(event) {
    if (this.screenshotValue === "no" && this.verdictValue === "approved") {
      event.preventDefault();
    }
  }

  get screenshotValue() {
    return this.element.querySelector(
      'input[name="screenshot_verified"]:checked',
    )?.value;
  }

  get verdictValue() {
    return this.element.querySelector(
      'input[name="certification_ship[status]"]:checked',
    )?.value;
  }
}
