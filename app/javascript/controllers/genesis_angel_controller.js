import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["speech"];
  static values = { lines: Array, index: { type: Number, default: 0 } };
  dismiss(event) {
    event.stopPropagation();

    const token = document.querySelector("meta[name='csrf-token']")?.content;
    fetch("/my/dismissals", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token || "",
      },
      body: JSON.stringify({ thing_name: "genesis_angel" }),
    }).catch(() => {});

    this.element.remove();
  }
  advance(event) {
    event.stopPropagation();
    if (this.indexValue >= this.linesValue.length - 1)
      return this.dismiss(event);
    this.indexValue++;
  }

  indexValueChanged() {
    this.speechTarget.textContent = this.linesValue[this.indexValue];
  }
}
