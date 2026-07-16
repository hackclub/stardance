import { Controller } from "@hotwired/stimulus";

// Optimistic, animated like button.
//
// The like button renders in many contexts — the home feed, profile feeds,
// project pages, the devlog page — and several of those live inside Turbo
// Frames with `target="_top"` (or `turbo: false` regions) where a plain form
// submission triggers a full page navigation instead of an in-place update.
//
// This controller intercepts the form submit, updates the UI instantly (so the
// heart animation always plays), and persists the change with a background
// fetch. Liking therefore never navigates or reloads the page, regardless of
// the surrounding Turbo context.
//
// The wrapping <form> (button_to) stays as a no-JS fallback: without this
// controller it submits normally and the Turbo Stream response updates the
// button.
export default class extends Controller {
  static values = {
    liked: Boolean,
    count: Number,
    url: String,
  };

  static targets = ["button", "count"];

  connect() {
    // Last state the server is known to agree with — used to reconcile the
    // optimistic UI and to roll it back if a request fails.
    this.syncedLiked = this.likedValue;
    this.syncedCount = this.countValue;
  }

  toggle(event) {
    event.preventDefault();

    this.likedValue = !this.likedValue;
    this.countValue = Math.max(0, this.countValue + (this.likedValue ? 1 : -1));
    if (this.likedValue) this.#animate();

    this.#scheduleSync();
  }

  likedValueChanged() {
    if (!this.hasButtonTarget) return;
    this.buttonTarget.classList.toggle(
      "like-button__btn--liked",
      this.likedValue,
    );
    this.buttonTarget.setAttribute("aria-pressed", String(this.likedValue));
  }

  countValueChanged() {
    if (this.hasCountTarget) this.countTarget.textContent = this.countValue;
  }

  #animate() {
    if (!this.hasButtonTarget) return;
    const btn = this.buttonTarget;
    btn.classList.remove("like-button__btn--animate");
    // Force a reflow so the animation restarts on rapid re-likes.
    void btn.offsetWidth;
    btn.classList.add("like-button__btn--animate");
  }

  #scheduleSync() {
    clearTimeout(this.syncTimer);
    // Collapse rapid toggles into a single request for the settled state.
    this.syncTimer = setTimeout(() => this.#sync(), 250);
  }

  async #sync() {
    if (this.inFlight) {
      this.#scheduleSync();
      return;
    }

    const desired = this.likedValue;
    if (desired === this.syncedLiked) return;

    this.inFlight = true;
    try {
      const response = await fetch(this.urlValue, {
        method: desired ? "POST" : "DELETE",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.#csrfToken,
          "X-Requested-With": "XMLHttpRequest",
        },
        credentials: "same-origin",
      });
      if (!response.ok) {
        throw new Error(`Like request failed: ${response.status}`);
      }

      const data = await response.json();
      this.syncedLiked = data.liked;
      this.syncedCount = data.count;

      // Adopt the authoritative count only if the user has settled on the
      // same state the server now reflects, so we don't clobber a re-toggle.
      if (this.likedValue === data.liked) this.countValue = data.count;
    } catch {
      // Request failed (offline, 4xx, etc.) — roll back to the last
      // server-confirmed state.
      this.likedValue = this.syncedLiked;
      this.countValue = this.syncedCount;
    } finally {
      this.inFlight = false;
      // The user toggled again while the request was in flight — keep syncing.
      if (this.likedValue !== this.syncedLiked) this.#scheduleSync();
    }
  }

  get #csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || "";
  }
}
