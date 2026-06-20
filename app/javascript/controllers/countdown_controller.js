import { Controller } from "@hotwired/stimulus";

// Live "Xh Ymin" countdown to a fixed instant (the next daily reset). Ticks
// every half-minute so the minute display stays current; clamps at zero.
export default class extends Controller {
  static values = { resetAt: String };

  connect() {
    this.render();
    this.timer = setInterval(() => this.render(), 30_000);
  }

  disconnect() {
    clearInterval(this.timer);
  }

  render() {
    const remaining = new Date(this.resetAtValue).getTime() - Date.now();
    const secs = Math.max(0, Math.floor(remaining / 1000));
    const hours = Math.floor(secs / 3600);
    const mins = Math.floor((secs % 3600) / 60);
    this.element.textContent = `${hours}h ${mins}min`;
  }
}
