import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["card"];

  close() {
    this.element.close();
  }

  remove() {
    this.element.remove();
  }

  connect() {
    if (!this.element.open) this.element.showModal();
  }

  backdropClose(event) {
    if (this.hasCardTarget && this.cardTarget.contains(event.target)) return;
    this.close();
  }
}
