import { Controller } from "@hotwired/stimulus";
import { serverClock } from "../lib/server_clock.js";

// Live countdown to a fixed instant. Ticks every half-minute so the minute
// display stays current; includes days for longer windows and clamps at zero.
// With the clock value set it ticks every second as DD:HH:MM:SS instead, each
// digit in its own span so CSS can give proportional fonts fixed-width slots.
// With seconds set it ticks every second as plain text ("1d 04:12:09").
export default class extends Controller {
  static values = {
    resetAt: String,
    expiredText: String,
    clock: Boolean,
    seconds: Boolean,
  };

  connect() {
    this.unsubscribeClock = serverClock.subscribe(() => this.render());
    this.render();
    this.timer = setInterval(
      () => this.render(),
      this.clockValue || this.secondsValue ? 1000 : 30_000,
    );
  }

  resetAtValueChanged() {
    this.render();
  }

  disconnect() {
    this.unsubscribeClock?.();
    clearInterval(this.timer);
  }

  render() {
    const remaining = new Date(this.resetAtValue).getTime() - serverClock.now();
    if (!Number.isFinite(remaining)) return;
    if (remaining <= 0 && this.hasExpiredTextValue) {
      this.element.textContent = this.expiredTextValue;
      clearInterval(this.timer);
      return;
    }

    const secs = Math.max(0, Math.ceil(remaining / 1000));
    const totalHours = Math.floor(secs / 3600);
    const days = Math.floor(totalHours / 24);
    const hours = totalHours % 24;
    const mins = Math.floor((secs % 3600) / 60);
    if (this.clockValue) {
      this.element.classList.toggle("buku-x3-status__clock--urgent", secs <= 3);
      this.element.innerHTML = [days, hours, mins, secs % 60]
        .map((n) =>
          [...String(n).padStart(2, "0")]
            .map((d) => `<span>${d}</span>`)
            .join(""),
        )
        .join(":");
      return;
    }
    if (this.secondsValue) {
      const clock = [hours, mins, secs % 60]
        .map((n) => String(n).padStart(2, "0"))
        .join(":");
      this.element.textContent = days > 0 ? `${days}d ${clock}` : clock;
      return;
    }
    this.element.textContent =
      days > 0 ? `${days}d ${hours}h ${mins}min` : `${hours}h ${mins}min`;
  }
}
