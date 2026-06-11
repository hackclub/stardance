import { Controller } from "@hotwired/stimulus";

// data-controller="event-time"
//
// Re-renders an event timestamp in the viewer's local timezone. The server
// renders a UTC fallback into the element; on connect this swaps it for
// "happening now", a relative lead-in, or a local weekday/date.
export default class extends Controller {
  static values = { start: String, end: String };

  connect() {
    const start = new Date(this.startValue);
    if (Number.isNaN(start.getTime())) return;

    const end = this.endValue ? new Date(this.endValue) : null;
    const text = this.format(start, end, new Date());
    if (text) this.element.textContent = text;
  }

  format(start, end, now) {
    if (end && start <= now && now <= end) return "happening now";

    const minute = 60 * 1000;
    const diff = start - now;
    if (Math.abs(diff) < minute) return "now";
    if (diff < 0) return null; // started, end unknown/passed — keep fallback

    if (diff < 60 * minute) return `in ${Math.ceil(diff / minute)}min`;
    if (diff < 24 * 60 * minute)
      return `in ${Math.round(diff / (60 * minute))}h`;
    if (diff < 7 * 24 * 60 * minute) {
      return new Intl.DateTimeFormat(undefined, {
        weekday: "short",
        hour: "numeric",
        minute: "2-digit",
      }).format(start);
    }
    return new Intl.DateTimeFormat(undefined, {
      month: "short",
      day: "numeric",
    }).format(start);
  }
}
