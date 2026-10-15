import { Controller } from "@hotwired/stimulus";

// Copies the API key to the clipboard and swaps the element's own text to
// "Copied!" for a moment, instead of a floating tooltip (which has trouble
// positioning correctly inside the settings dialog — see tooltip_controller).
export default class extends Controller {
  static values = { text: String };

  connect() {
    this.originalText = this.element.textContent;
  }

  disconnect() {
    clearTimeout(this.revertTimeout);
  }

  async copy(event) {
    event.preventDefault();

    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard
        .writeText(this.textValue)
        .catch(() => this.#fallback());
    } else {
      this.#fallback();
    }

    clearTimeout(this.revertTimeout);
    this.element.textContent = "Copied!";
    this.revertTimeout = setTimeout(() => {
      this.element.textContent = this.originalText;
    }, 1200);
  }

  #fallback() {
    const ta = document.createElement("textarea");
    ta.value = this.textValue;
    ta.style.cssText = "position:fixed;opacity:0";
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    ta.remove();
  }
}
