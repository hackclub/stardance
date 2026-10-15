import { Controller } from "@hotwired/stimulus";

const STORAGE_KEY = "fraud-speedrun";

// Speedrun skips the payout celebration and opens the next person as soon as
// this one is cleared. Target callbacks run before connect(), so the setting
// is read from storage each time rather than cached on connect.
export default class extends Controller {
  static targets = ["toggle", "celebration", "next"];

  toggleTargetConnected(toggle) {
    toggle.checked = this.#enabled;
  }

  toggle(event) {
    localStorage.setItem(STORAGE_KEY, event.target.checked);
  }

  celebrationTargetConnected(celebration) {
    if (this.#enabled) celebration.remove();
  }

  nextTargetConnected(link) {
    if (this.#enabled) link.click();
  }

  get #enabled() {
    return localStorage.getItem(STORAGE_KEY) === "true";
  }
}
