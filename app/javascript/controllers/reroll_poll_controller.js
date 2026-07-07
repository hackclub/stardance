import { Controller } from "@hotwired/stimulus";

// Lives on the locked reroll button. The unlock gate (coding time today) is
// refreshed by a throttled background job, so the button can go stale on an
// open page. This re-fetches the reroll control (plain fetch, no Turbo) on an
// interval and swaps it in place the moment it comes back unlocked — then
// stops. Polling pauses while the tab is hidden and gives up after a cap so an
// idle page never polls forever.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 15000 },
    maxPolls: { type: Number, default: 60 },
  };

  connect() {
    this.polls = 0;
    this.onVisibility = () => this.sync();
    document.addEventListener("visibilitychange", this.onVisibility);
    this.sync();
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility);
    this.stop();
  }

  // Run only while the tab is visible.
  sync() {
    document.hidden ? this.stop() : this.start();
  }

  start() {
    if (this.timer) return;
    this.timer = setInterval(() => this.poll(), this.intervalValue);
  }

  stop() {
    clearInterval(this.timer);
    this.timer = null;
  }

  async poll() {
    if (this.polls++ >= this.maxPollsValue) return this.stop();

    let html;
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/html" },
      });
      if (!response.ok) return this.stop();
      html = (await response.text()).trim();
    } catch {
      return; // transient network error — try again next tick
    }
    if (!html) return this.stop(); // no roll / feature off

    const state = new DOMParser()
      .parseFromString(html, "text/html")
      .querySelector("[data-reroll-state]")?.dataset.rerollState;

    // Still locked: leave the button (and its tooltip) untouched, keep waiting.
    if (!state || state === "locked") return;

    // Unlocked (or used elsewhere): swap in the new control. The replacement
    // carries no controller, so polling ends here.
    this.stop();
    this.element.outerHTML = html;
  }
}
