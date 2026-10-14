import { Controller } from "@hotwired/stimulus";

// A dismissable notice. Persists the dismissal in a cookie (cookie value) or,
// for a per-account notice, via /my/dismissals (thing value). Set the open
// value on a <dialog> to have it show itself as soon as it connects.
export default class extends Controller {
  static values = { cookie: String, thing: String, open: Boolean };

  connect() {
    if (this.openValue && typeof this.element.showModal === "function") {
      this.element.showModal();
    }
  }

  dismiss() {
    if (this.cookieValue) {
      document.cookie = `${this.cookieValue}=1; path=/; max-age=${60 * 60 * 24 * 365}`;
    }

    if (this.thingValue) {
      const token = document.querySelector("meta[name='csrf-token']")?.content;
      fetch("/my/dismissals", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token || "",
        },
        body: JSON.stringify({ thing_name: this.thingValue }),
      }).catch(() => {});
    }

    this.element.remove();
  }
}
