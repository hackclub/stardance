import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["menu"];
  static values = { url: String };

  connect() {
    this._onClickOutside = this._onClickOutside.bind(this);
    this._onKeydown = this._onKeydown.bind(this);
  }

  disconnect() {
    document.removeEventListener("click", this._onClickOutside);
    document.removeEventListener("keydown", this._onKeydown);
  }

  toggle(event) {
    event.stopPropagation();

    if (this.menuTarget.hidden) {
      this._open();
    } else {
      this._close();
    }
  }

  share(event) {
    event.preventDefault();
    const url = new URL(this.urlValue, window.location.origin).href;

    navigator.clipboard.writeText(url).then(() => {
      const button = event.currentTarget;
      const original = button.textContent;
      button.textContent = "Copied!";
      setTimeout(() => {
        button.textContent = original;
      }, 1500);
    });

    this._close();
  }

  // private

  _open() {
    this.menuTarget.hidden = false;
    document.addEventListener("click", this._onClickOutside);
    document.addEventListener("keydown", this._onKeydown);
  }

  _close() {
    this.menuTarget.hidden = true;
    document.removeEventListener("click", this._onClickOutside);
    document.removeEventListener("keydown", this._onKeydown);
  }

  _onClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this._close();
    }
  }

  _onKeydown(event) {
    if (event.key === "Escape") {
      this._close();
    }
  }
}
