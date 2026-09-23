import { Controller } from "@hotwired/stimulus";

// Claim countdown, ticking every second: the reviewer is watching a hold they can lose.
export default class extends Controller {
  static values = { expiresAt: String, expiredText: String };

  connect() {
    this.render();
    this.timer = setInterval(() => this.render(), 1000);
  }

  disconnect() {
    clearInterval(this.timer);
  }

  render() {
    const remaining = new Date(this.expiresAtValue).getTime() - Date.now();

    if (remaining <= 0) {
      this.element.textContent = this.expiredTextValue || "Claim expired";
      clearInterval(this.timer);
      return;
    }

    const secs = Math.floor(remaining / 1000);
    const hh = String(Math.floor(secs / 3600)).padStart(2, "0");
    const mm = String(Math.floor((secs % 3600) / 60)).padStart(2, "0");
    const ss = String(secs % 60).padStart(2, "0");
    this.element.textContent = `Claim ending in ${hh}h:${mm}m:${ss}s`;
  }
}
