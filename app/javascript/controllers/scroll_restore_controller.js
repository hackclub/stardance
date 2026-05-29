import { Controller } from "@hotwired/stimulus";

// Persists scrollY across form submits so the manage edit page doesn't snap
// to top after every inline action. Link clicks still reset normally.
export default class extends Controller {
  connect() {
    this.restoreOnce();
    this.handler = this.save.bind(this);
    this.element.addEventListener("submit", this.handler, true);
  }

  disconnect() {
    if (this.handler) {
      this.element.removeEventListener("submit", this.handler, true);
    }
  }

  storageKey() {
    return `stardance:scroll:${window.location.pathname}${window.location.search}`;
  }

  save() {
    try {
      sessionStorage.setItem(this.storageKey(), String(window.scrollY));
    } catch {}
  }

  restoreOnce() {
    try {
      const raw = sessionStorage.getItem(this.storageKey());
      if (!raw) return;
      sessionStorage.removeItem(this.storageKey());
      const y = parseInt(raw, 10);
      if (Number.isNaN(y)) return;
      // Wait a frame so layout settles before scrolling.
      requestAnimationFrame(() => window.scrollTo(0, y));
    } catch {}
  }
}
