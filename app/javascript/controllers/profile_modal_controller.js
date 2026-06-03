import { Controller } from "@hotwired/stimulus";

// Opens the followers/following modal, fetches the list HTML, swaps it in.
// One controller instance is bound to the <dialog>. Triggers from outside
// (the count buttons) call `open` with `profile-modal-url-param` and
// `profile-modal-title-param`.
export default class extends Controller {
  static targets = ["dialog", "title", "body"];

  open(event) {
    const url = event.params.url;
    const title = event.params.title || "";
    if (!url) return;

    const dialog = this._dialog();
    if (!dialog) return;

    if (this.hasTitleTarget && title) this.titleTarget.textContent = title;
    if (this.hasBodyTarget)
      this.bodyTarget.innerHTML =
        '<p class="followers-modal__loading">Loading…</p>';

    dialog.showModal?.() || dialog.setAttribute("open", "");

    fetch(url, { headers: { Accept: "text/html" } })
      .then((r) => (r.ok ? r.text() : Promise.reject(r.status)))
      .then((html) => {
        if (this.hasBodyTarget) this.bodyTarget.innerHTML = html;
      })
      .catch(() => {
        if (this.hasBodyTarget)
          this.bodyTarget.innerHTML =
            '<p class="follow-list__empty">Could not load.</p>';
      });
  }

  close() {
    const dialog = this._dialog();
    if (!dialog) return;
    dialog.close?.() || dialog.removeAttribute("open");
  }

  backdropClose(event) {
    const dialog = this._dialog();
    if (!dialog) return;
    const rect = dialog.getBoundingClientRect();
    const clickedInside =
      rect.top <= event.clientY &&
      event.clientY <= rect.top + rect.height &&
      rect.left <= event.clientX &&
      event.clientX <= rect.left + rect.width;
    if (!clickedInside) this.close();
  }

  _dialog() {
    if (this.hasDialogTarget) return this.dialogTarget;
    return document.getElementById("followers-modal");
  }
}
