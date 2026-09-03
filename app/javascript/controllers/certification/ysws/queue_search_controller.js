import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "frame", "clear"];
  static values = {
    url: String,
    debounce: { type: Number, default: 150 },
    minLength: { type: Number, default: 2 },
  };

  connect() {
    this.timer = null;
    this.lastQuery = this.#query();
    this.#syncClearButton();
    this.onFrameLoad = (event) => {
      if (event.target === this.frameTarget)
        this.element.classList.remove("is-searching");
    };
    this.element.addEventListener("turbo:frame-load", this.onFrameLoad);
  }

  disconnect() {
    clearTimeout(this.timer);
    this.element.removeEventListener("turbo:frame-load", this.onFrameLoad);
  }

  search() {
    clearTimeout(this.timer);
    this.#syncClearButton();
    this.timer = setTimeout(() => this.#run(), this.debounceValue);
  }

  submit(event) {
    event.preventDefault();
    clearTimeout(this.timer);
    this.#run({ force: true });
  }

  clear() {
    this.inputTarget.value = "";
    this.search();
    this.inputTarget.focus();
  }

  #run({ force = false } = {}) {
    const query = this.#query();
    if (!force && query.length > 0 && query.length < this.minLengthValue)
      return;
    if (query === this.lastQuery) return;
    this.lastQuery = query;

    const url = new URL(this.urlValue, window.location.origin);
    if (query) url.searchParams.set("search", query);

    this.element.classList.add("is-searching");
    this.frameTarget.src = url.toString();
    history.replaceState({}, "", url.toString());
  }

  #query() {
    return this.inputTarget.value.trim();
  }

  #syncClearButton() {
    if (this.hasClearTarget)
      this.clearTarget.hidden = this.#query().length === 0;
  }
}
