import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["time"];
  static values = {
    url: String,
    interval: { type: Number, default: 60000 },
  };

  connect() {
    this.#fetch();
    this.timer = setInterval(() => this.#fetch(), this.intervalValue);
  }

  disconnect() {
    clearInterval(this.timer);
  }

  async #fetch() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json", "X-Requested-With": "XMLHttpRequest" },
      });
      if (!response.ok) return;
      const { formatted } = await response.json();
      if (formatted) this.timeTarget.textContent = formatted;
    } catch {
      // network error — leave the displayed value as-is
    }
  }
}
