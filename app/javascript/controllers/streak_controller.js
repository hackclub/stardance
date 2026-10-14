import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "countdown",
    "weekView",
    "calendarView",
    "calendarContent",
    "toggleBtn",
    "toggleText",
    "toggleArrow",
  ];
  static values = {
    nextDay: String,
    timezone: String,
    month: Number,
    year: Number,
    monthUrl: String,
    firstMonth: Number,
    lastMonth: Number,
  };

  connect() {
    this.expanded = false;
    this.tick();
    this.timer = setInterval(() => this.tick(), 1000);
    this.detectTimezone();
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer);
  }

  tick() {
    if (!this.hasCountdownTarget) return;

    const now = new Date();
    const next = new Date(this.nextDayValue);
    const diff = next - now;

    if (diff <= 0) {
      this.countdownTarget.textContent = "00:00:00";
      return;
    }

    const hours = Math.floor(diff / 3600000);
    const minutes = Math.floor((diff % 3600000) / 60000);
    const seconds = Math.floor((diff % 60000) / 1000);

    this.countdownTarget.textContent = `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  }

  toggleCalendar() {
    this.expanded = !this.expanded;

    if (this.hasWeekViewTarget) this.weekViewTarget.hidden = this.expanded;
    if (this.hasCalendarViewTarget)
      this.calendarViewTarget.hidden = !this.expanded;
    if (this.hasToggleTextTarget) {
      this.toggleTextTarget.textContent = this.expanded
        ? "Hide calendar"
        : "View calendar";
    }
    this.element.classList.toggle("streak-widget--expanded", this.expanded);
  }

  prevMonth() {
    let m = this.monthValue - 1;
    let y = this.yearValue;
    if (m < 1) {
      m = 12;
      y -= 1;
    }
    if (y * 100 + m < this.firstMonthValue) return;

    this.monthValue = m;
    this.yearValue = y;
    this.fetchMonth();
  }

  nextMonth() {
    let m = this.monthValue + 1;
    let y = this.yearValue;
    if (m > 12) {
      m = 1;
      y += 1;
    }
    if (y * 100 + m > this.lastMonthValue) return;

    this.monthValue = m;
    this.yearValue = y;
    this.fetchMonth();
  }

  async fetchMonth() {
    if (!this.hasCalendarContentTarget) return;

    const url = `${this.monthUrlValue}?year=${this.yearValue}&month=${this.monthValue}`;
    try {
      const response = await fetch(url, {
        headers: { "X-Requested-With": "XMLHttpRequest" },
      });
      if (response.ok) {
        this.calendarContentTarget.innerHTML = await response.text();
      }
    } catch (e) {
      // silently fail
    }
  }

  detectTimezone() {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (!tz || tz === this.timezoneValue) return;

    document.cookie = `timezone=${tz};path=/;max-age=${60 * 60 * 24 * 365};SameSite=Lax`;

    if (this.timezoneValue === "UTC" || !this.timezoneValue) {
      fetch("/streaks/timezone", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            ?.content,
        },
        body: JSON.stringify({ timezone: tz }),
      });
    }
  }
}
