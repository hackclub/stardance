import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    if (!this.element.open) {
      this.element.showModal();
    }

    this._boundBackdropClick = this.backdropClick.bind(this);
    this.element.addEventListener("click", this._boundBackdropClick);

    this._boundClose = this.onClose.bind(this);
    this.element.addEventListener("close", this._boundClose);
  }

  disconnect() {
    this.element.removeEventListener("click", this._boundBackdropClick);
    this.element.removeEventListener("close", this._boundClose);
  }

  close() {
    this.element.close();
  }

  backdropClick(event) {
    // A real backdrop click on a <dialog> fires with event.target === the dialog
    // itself. Clicks on anything inside bubble up here too, including backdrop
    // clicks on the nested name prompt, which must not close this dialog (that
    // would navigate the builder away mid-create).
    if (event.target !== this.element) return;

    const rect = this.element.getBoundingClientRect();
    const inside =
      event.clientX >= rect.left &&
      event.clientX <= rect.right &&
      event.clientY >= rect.top &&
      event.clientY <= rect.bottom;

    if (!inside) this.element.close();
  }

  onClose() {
    if (history.length > 1) {
      history.back();
    } else {
      window.location.href = this.element.dataset.homeUrl;
    }
  }
}
