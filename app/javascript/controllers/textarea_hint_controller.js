import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["hint"];

  paste() {
    this.hintTarget.classList.add("textarea-hint--flash");
    this.hintTarget.addEventListener(
      "animationend",
      () => this.hintTarget.classList.remove("textarea-hint--flash"),
      { once: true },
    );
  }
}
