import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["toggle"];

  connect() {
    this.close();
    this.boundCloseOnEscape = this.closeOnEscape.bind(this);
    document.addEventListener("keydown", this.boundCloseOnEscape);
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundCloseOnEscape);
  }

  toggle() {
    this.setOpen(!this.element.classList.contains("discover-rail--open"));
  }

  close() {
    this.setOpen(false);
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close();
  }

  setOpen(open) {
    this.element.classList.toggle("discover-rail--open", open);
    this.toggleTarget.setAttribute("aria-expanded", String(open));
    this.toggleTarget.setAttribute(
      "aria-label",
      open ? "Close discover panel" : "Open discover panel",
    );
  }
}
