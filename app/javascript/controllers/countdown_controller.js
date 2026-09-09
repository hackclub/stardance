import { Controller } from "@hotwired/stimulus";

// Live countdown to a fixed instant. Ticks every half-minute so the minute
// display stays current; includes days for longer windows and clamps at zero.
export default class extends Controller {
  static values = { resetAt: String, expiredText: String };

  connect() {
    this.render();
    this.timer = setInterval(() => this.render(), 30_000);
  }

  disconnect() {
    clearInterval(this.timer);
  }

  render() {
    const remaining = new Date(this.resetAtValue).getTime() - Date.now();
    if (remaining <= 0 && this.hasExpiredTextValue) {
      this.element.textContent = this.expiredTextValue;
      clearInterval(this.timer);
      return;
    }

    const secs = Math.max(0, Math.floor(remaining / 1000));
    const totalHours = Math.floor(secs / 3600);
    const days = Math.floor(totalHours / 24);
    const hours = totalHours % 24;
    const mins = Math.floor((secs % 3600) / 60);
    this.element.textContent = days > 0 ? `${days}d ${hours}h ${mins}min` : `${hours}h ${mins}min`;
  }
}
