import { Controller } from "@hotwired/stimulus";

// Reuse the blackhole's existing poll so the meter and site damage agree.
export default class extends Controller {
  static targets = ["meter", "amount", "bukuHours", "beanHours", "toggle"];
  static values = { liveHours: Object };

  toggleRole() {
    const open = this.element.toggleAttribute("data-role-open");
    this.toggleTarget.setAttribute("aria-pressed", String(open));
  }

  dismissRole() {
    this.element.removeAttribute("data-role-open");
    this.toggleTarget.setAttribute("aria-pressed", "false");
    this.toggleTarget.blur();
  }

  refresh() {
    // Refresh just the home strip after the real reveal is saved. Preview
    // animations never emit completion or change account dismissals.
    if (!this.element.isConnected || this.element.tagName !== "TURBO-FRAME")
      return;
    const url = window.location.href;
    if (this.element.src === url) this.element.reload();
    else this.element.src = url;
  }

  update({ detail: { percent, hours } }) {
    if (!this.hasMeterTarget || !Number.isFinite(percent)) return;
    const value = Math.min(100, Math.max(0, percent));
    const label = `${Math.round(value * 10) / 10}% damaged`;
    this.meterTarget.setAttribute("aria-valuenow", value);
    this.meterTarget.setAttribute(
      "aria-valuetext",
      `${label}; bukus pull left, beans pull right`,
    );
    this.meterTarget.style.setProperty("--tug-position", `${100 - value}%`);
    this.amountTarget.textContent = label;
    if (hours) this.liveHoursValue = hours;
    const totals = hours || this.liveHoursValue;
    const formatter = new Intl.NumberFormat("en-US", {
      maximumFractionDigits: 1,
    });
    for (const team of ["buku", "bean"]) {
      if (!Number.isFinite(totals[team]) || totals[team] < 0) continue;
      const target =
        team === "buku" ? this.bukuHoursTarget : this.beanHoursTarget;
      target.textContent = formatter.format(totals[team]);
    }
  }
}
