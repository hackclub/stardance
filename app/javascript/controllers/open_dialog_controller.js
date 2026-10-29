import { Controller } from "@hotwired/stimulus";

// Opens the dialog with the given id on page load, then drops the query param
// that asked for it so a refresh or back navigation doesn't reopen it.
export default class extends Controller {
  static values = { id: String, param: String };

  connect() {
    const dialog = document.getElementById(this.idValue);
    if (dialog && !dialog.open) dialog.showModal();

    if (!this.paramValue) return;
    const params = new URLSearchParams(window.location.search);
    params.delete(this.paramValue);
    const query = params.toString();
    window.history.replaceState(
      window.history.state,
      "",
      `${window.location.pathname}${query ? `?${query}` : ""}${window.location.hash}`,
    );
  }
}
