import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "results", "widgets", "clearButton"];
  static values = { url: String };

  connect() {
    this._timer = null;
  }

  disconnect() {
    clearTimeout(this._timer);
  }

  search() {
    const query = this.inputTarget.value.trim();
    clearTimeout(this._timer);

    if (!query) {
      this.clearButtonTarget.hidden = true;
      this.resultsTarget.hidden = true;
      this.resultsTarget.removeAttribute("src");
      this.resultsTarget.innerHTML = "";
      this.widgetsTarget.hidden = false;
      return;
    }

    this.clearButtonTarget.hidden = false;
    this.widgetsTarget.hidden = true;
    this.resultsTarget.hidden = false;
    this.resultsTarget.innerHTML =
      '<p class="discover-rail__placeholder-text">Searching...</p>';
    this._timer = setTimeout(() => this._loadResults(query), 180);
  }

  _loadResults(query) {
    const url = new URL(this.urlValue, window.location.origin);
    url.searchParams.set("q", query);
    url.searchParams.set("surface", "discover_rail");
    this.resultsTarget.src = url.toString();
  }

  clear() {
    this.inputTarget.value = "";
    this.search();
    this.inputTarget.focus();
  }
}
