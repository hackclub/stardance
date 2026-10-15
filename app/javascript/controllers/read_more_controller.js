import { Controller } from "@hotwired/stimulus";

// Collapses long feed post bodies to a few lines. The toggle only appears
// when the body actually overflows its clamped height.
export default class extends Controller {
  static targets = ["body", "toggle"];
  static classes = ["clamped"];

  connect() {
    if (this.overflowing()) {
      this.toggleTarget.hidden = false;
    } else {
      this.bodyTarget.classList.remove(this.clampedClass);
    }
  }

  toggle() {
    const clamped = this.bodyTarget.classList.toggle(this.clampedClass);
    this.toggleTarget.textContent = clamped ? "Read more" : "Show less";
  }

  overflowing() {
    return this.bodyTarget.scrollHeight > this.bodyTarget.clientHeight + 1;
  }
}
