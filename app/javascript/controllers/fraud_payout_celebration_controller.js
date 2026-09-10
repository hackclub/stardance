import { Controller } from "@hotwired/stimulus";

// Plays once when a person is fully reviewed: the amount just earned drains
// into the reviewer's running unpaid total. The bursts themselves are CSS, so
// this only drives the two counters and clears the overlay afterwards.
export default class extends Controller {
  static targets = ["amount", "total"];
  static values = {
    amount: Number,
    total: Number,
    hold: { type: Number, default: 2200 },
    duration: { type: Number, default: 1400 },
    tail: { type: Number, default: 1400 },
  };

  connect() {
    const reduced =
      window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;

    if (reduced) {
      this.#render(0, this.totalValue);
      this.#scheduleDismiss(0);
      return;
    }

    this.element.classList.add("fraud-celebration--playing");

    // The stylesheet delays the total on the same hold, so the pause lives in
    // one place rather than being written out twice and drifting.
    this.element.style.setProperty(
      "--fraud-celebration-hold",
      `${this.holdValue}ms`,
    );

    // The amount earned sits on its own first. Only once it has been read does
    // it start draining into the running total.
    this.#render(this.amountValue, this.totalValue - this.amountValue);

    this.holdTimer = setTimeout(() => {
      this.startTime = performance.now();
      this.#tick();
    }, this.holdValue);

    this.#scheduleDismiss(this.holdValue + this.durationValue + this.tailValue);
  }

  disconnect() {
    clearTimeout(this.holdTimer);
    clearTimeout(this.dismissTimer);
    cancelAnimationFrame(this.frame);
  }

  // Dismissing early is always available: the overlay covers the queue.
  dismiss() {
    this.element.remove();
  }

  #tick() {
    const progress = Math.min(
      (performance.now() - this.startTime) / this.durationValue,
      1,
    );
    const eased = 1 - Math.pow(1 - progress, 4);

    this.#render(
      this.amountValue * (1 - eased),
      this.totalValue - this.amountValue * (1 - eased),
    );

    if (progress < 1) this.frame = requestAnimationFrame(() => this.#tick());
  }

  #render(amount, total) {
    if (this.hasAmountTarget)
      this.amountTarget.textContent = this.#format(amount);
    if (this.hasTotalTarget) this.totalTarget.textContent = this.#format(total);
  }

  #scheduleDismiss(delay) {
    this.dismissTimer = setTimeout(() => this.dismiss(), delay);
  }

  #format(n) {
    return (Math.round(n * 100) / 100).toLocaleString(undefined, {
      maximumFractionDigits: 2,
    });
  }
}
