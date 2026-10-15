import { Controller } from "@hotwired/stimulus";

// Mirrors Workshop#state: joinWindowMs comes from the server so the join
// reveal can't drift from the server-side joinable? check.
export default class extends Controller {
  static values = {
    startsAt: String,
    endsAt: String,
    joinWindowMs: { type: Number, default: 15 * 60 * 1000 },
  };
  static targets = ["label", "join", "time", "rsvp"];

  connect() {
    this.startsAt = new Date(this.startsAtValue).getTime();
    this.endsAt = new Date(this.endsAtValue).getTime();
    this.renderLocalTime();
    this.tick();
    this.timer = setInterval(() => this.tick(), 1000);
  }

  disconnect() {
    clearInterval(this.timer);
  }

  tick() {
    const now = Date.now();

    if (now > this.endsAt) {
      this.labelTarget.textContent = "This workshop has ended.";
      this.joinTarget.hidden = true;
      this.hideRsvp();
      clearInterval(this.timer);
    } else if (now >= this.startsAt) {
      this.labelTarget.textContent = `Ends in ${this.formatDuration(this.endsAt - now)}`;
      this.joinTarget.hidden = false;
      this.hideRsvp();
    } else if (now >= this.startsAt - this.joinWindowMsValue) {
      this.labelTarget.textContent = `Starting in ${this.formatDuration(this.startsAt - now)}`;
      this.joinTarget.hidden = false;
    } else {
      this.labelTarget.textContent = `Starts in ${this.formatDuration(this.startsAt - now)}`;
      this.joinTarget.hidden = true;
    }
  }

  hideRsvp() {
    if (this.hasRsvpTarget) this.rsvpTarget.hidden = true;
  }

  renderLocalTime() {
    if (!this.hasTimeTarget) return;

    const start = new Date(this.startsAtValue);
    const end = new Date(this.endsAtValue);
    const day = start.toLocaleDateString([], {
      weekday: "long",
      month: "long",
      day: "numeric",
    });
    const timeOpts = { hour: "numeric", minute: "2-digit" };
    const endOpts = { ...timeOpts, timeZoneName: "short" };
    this.timeTarget.textContent = `${day} · ${start.toLocaleTimeString([], timeOpts)} – ${end.toLocaleTimeString([], endOpts)}`;
  }

  formatDuration(ms) {
    const total = Math.max(0, Math.floor(ms / 1000));
    const days = Math.floor(total / 86400);
    const hours = Math.floor((total % 86400) / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const seconds = total % 60;

    if (days > 0) return `${days}d ${hours}h ${minutes}m`;
    if (hours > 0) return `${hours}h ${minutes}m ${seconds}s`;
    return `${minutes}m ${seconds}s`;
  }
}
