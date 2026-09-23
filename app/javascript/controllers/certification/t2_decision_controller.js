import { Controller } from "@hotwired/stimulus";

// Approve/return, then confirm in a <dialog> that says what the verdict costs.
export default class extends Controller {
  static targets = [
    "feedback",
    "approve",
    "return",
    "confirm",
    "confirmText",
    "amount",
  ];
  static values = {
    approveText: String,
    grantText: String,
    returnText: String,
  };

  approve(event) {
    event.preventDefault();
    this.choose("approved");
  }

  returnIt(event) {
    event.preventDefault();
    if (this.hasFeedbackTarget && this.feedbackTarget.value.trim() === "") {
      this.feedbackTarget.setCustomValidity(
        "Tell the builder why this is being returned.",
      );
      this.feedbackTarget.reportValidity();
      this.feedbackTarget.addEventListener(
        "input",
        () => this.feedbackTarget.setCustomValidity(""),
        {
          once: true,
        },
      );
      return;
    }
    this.choose("returned");
  }

  choose(verdict) {
    const radio =
      verdict === "approved" ? this.approveTarget : this.returnTarget;
    radio.checked = true;

    if (this.hasConfirmTextTarget) {
      this.confirmTextTarget.textContent =
        verdict === "approved" ? this.approveText() : this.returnTextValue;
    }
    if (this.hasConfirmTarget) this.confirmTarget.showModal();
  }

  // Name the typed override in the confirmation: it's what HCB will be asked for.
  approveText() {
    if (!this.hasAmountTarget || !this.grantTextValue)
      return this.approveTextValue;

    const amount = this.amountTarget.value || this.amountTarget.placeholder;
    return this.grantTextValue.replace("%{amount}", amount);
  }

  cancel() {
    if (this.hasConfirmTarget) this.confirmTarget.close();
  }

  submit() {
    if (this.hasConfirmTarget) this.confirmTarget.close();
    this.element.requestSubmit();
  }
}
