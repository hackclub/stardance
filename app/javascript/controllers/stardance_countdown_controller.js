import { Controller } from "@hotwired/stimulus";
import { serverClock } from "../lib/server_clock.js";

// Switch the visible and accessible clocks together without starting a finale.
export default class extends Controller {
  static targets = ["label", "clock"];
  static values = { endsAt: String, explodesAt: String, overrideAt: String };

  connect() {
    this.unsubscribeClock = serverClock.subscribe(() => this.render());
    this.render();
    this.timer = setInterval(() => this.render(), 1000);
  }

  disconnect() {
    this.unsubscribeClock?.();
    clearInterval(this.timer);
  }

  overrideAtValueChanged() {
    this.render();
  }

  render(now = serverClock.now()) {
    if (!this.hasLabelTarget || !Number.isFinite(now)) return;
    const endsAt = Date.parse(this.endsAtValue);
    if (
      !Number.isFinite(endsAt) ||
      !Number.isFinite(Date.parse(this.explodesAtValue))
    )
      return;

    // Local previews and late arrivals temporarily replay the final 3–2–1.
    const overridden = Number.isFinite(Date.parse(this.overrideAtValue));
    const exploding = overridden || now >= endsAt;
    const deadline = overridden
      ? this.overrideAtValue
      : exploding
        ? this.explodesAtValue
        : this.endsAtValue;
    const label = exploding ? "stardance explodes in" : "stardance ends in";
    if (this.labelTarget.textContent !== label)
      this.labelTarget.textContent = label;
    this.clockTargets.forEach((clock) => {
      if (clock.getAttribute("data-countdown-reset-at-value") !== deadline)
        clock.setAttribute("data-countdown-reset-at-value", deadline);
    });
  }
}
