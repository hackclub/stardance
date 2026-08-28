import { Controller } from "@hotwired/stimulus";

// Live search for the YSWS review queue. Debounces typing, then drives the
// results turbo-frame by its `src` so only the table re-renders — the reviewer
// stats frame and the filter row stay put. The address bar is kept in sync so a
// search is shareable and survives a reload, and the enclosing GET form is left
// intact so pressing Enter still works with JS off.
export default class extends Controller {
  static targets = ["input", "frame", "clear"];
  static values = {
    url: String,
    // Long enough to swallow a burst of keystrokes, short enough that the table
    // lands before the next one.
    debounce: { type: Number, default: 150 },
    // A one-character query matches most of the table, which is slow to render
    // and useless to read. Clearing the box is still honoured immediately.
    minLength: { type: Number, default: 2 },
  };

  connect() {
    this.timer = null;
    this.lastQuery = this.#query();
    this.#syncClearButton();
    // turbo:frame-load bubbles, and the lazily loaded reviewer-stats frame is
    // also inside this element — so only the results frame clears the state.
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

  // Enter submits the enclosing GET form, which is the no-JS fallback and costs a
  // full page load. Once the frame is available it's strictly faster, so take
  // over — and honour the short query the debounce path holds back, since
  // pressing Enter is explicit intent rather than a pause in typing.
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
    // Backspacing to a query already on screen shouldn't cost a round trip.
    if (query === this.lastQuery) return;
    this.lastQuery = query;

    const url = new URL(this.urlValue, window.location.origin);
    if (query) url.searchParams.set("search", query);

    this.element.classList.add("is-searching");
    // Assigning src cancels any request already in flight, so a slow earlier
    // response can't land on top of a newer one.
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
