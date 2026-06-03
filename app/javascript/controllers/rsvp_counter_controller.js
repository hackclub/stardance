import { Controller } from "@hotwired/stimulus";

// Odometer-style counter with polling backoff. Each digit animates
// independently. Big jumps are broken into intermediate ticks so
// bursts of signups look organic.
//
// Backoff schedule:
//   0–15s:   poll every 500ms
//   15s–1m:  poll every 1s
//   1m–10m:  poll every 5s
//   10m–1h:  poll every 10s
//   1h+:     poll every 60s

const BACKOFF_TIERS = [
  { until: 15_000, interval: 500 },
  { until: 60_000, interval: 1_000 },
  { until: 600_000, interval: 5_000 },
  { until: 3_600_000, interval: 10_000 },
  { until: Infinity, interval: 60_000 },
];

export default class extends Controller {
  static values = { pollUrl: String };

  connect() {
    this.prefersReducedMotion =
      window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;

    this.span = this.element.querySelector("#rsvp_counter");
    if (!this.span) return;

    this.currentCount = parseInt(this.span.dataset.count, 10) || 0;
    this.animating = false;
    this.queue = [];
    this.tickDuration = null;
    this.startedAt = Date.now();

    this.buildDigits(this.currentCount);
    this.schedulePoll();
  }

  disconnect() {
    clearTimeout(this._pollTimer);
  }

  getInterval() {
    const elapsed = Date.now() - this.startedAt;
    for (const tier of BACKOFF_TIERS) {
      if (elapsed < tier.until) return tier.interval;
    }
    return 60_000;
  }

  schedulePoll() {
    this._pollTimer = setTimeout(() => this.poll(), this.getInterval());
  }

  async poll() {
    if (!this.pollUrlValue) {
      this.schedulePoll();
      return;
    }

    try {
      const resp = await fetch(this.pollUrlValue, {
        headers: { Accept: "application/json" },
      });
      if (resp.ok) {
        const { count } = await resp.json();
        if (typeof count === "number" && count !== this.currentCount) {
          this.applyNewCount(count);
        }
      }
    } catch {
      // retry on next poll
    }

    this.schedulePoll();
  }

  applyNewCount(newCount) {
    const oldCount = this.currentCount;
    this.currentCount = newCount;

    if (newCount < oldCount) {
      this.buildDigits(newCount);
      return;
    }

    const delta = newCount - oldCount;
    if (delta <= 1) {
      this.tickDuration = null;
      this.enqueue(newCount);
    } else {
      const maxTicks = Math.min(delta, 20);
      this.tickDuration = Math.max(80, Math.floor(1000 / maxTicks));
      const step = delta / maxTicks;
      for (let i = 1; i <= maxTicks; i++) {
        this.enqueue(Math.round(oldCount + step * i));
      }
    }
  }

  formatNumber(n) {
    return n.toLocaleString();
  }

  buildDigits(count) {
    const text = this.formatNumber(count);
    this.span.textContent = "";
    this.span.setAttribute("aria-label", text);
    this.span.dataset.count = count;
    this.digitEls = [];

    for (const ch of text) {
      const wrapper = document.createElement("span");
      wrapper.className = /\d/.test(ch)
        ? "rsvp-counter__digit"
        : "rsvp-counter__sep";

      const inner = document.createElement("span");
      inner.className = "rsvp-counter__digit-inner";
      inner.textContent = ch;
      wrapper.appendChild(inner);

      this.span.appendChild(wrapper);
      this.digitEls.push({ wrapper, inner, value: ch });
    }
  }

  enqueue(count) {
    if (this.animating) {
      this.queue.push(count);
    } else {
      this.animateToCount(count);
    }
  }

  animateToCount(count) {
    this.animating = true;

    const newText = this.formatNumber(count);
    const oldText = this.digitEls.map((d) => d.value).join("");

    if (newText.length !== oldText.length) {
      this.buildDigits(count);
      this.pulse();
      this.animating = false;
      this.drain();
      return;
    }

    const base = this.tickDuration || 680;
    const jitter = this.tickDuration ? base * (0.5 + Math.random()) : base;
    const duration = Math.round(jitter);

    const animations = [];
    for (let i = 0; i < newText.length; i++) {
      if (newText[i] !== this.digitEls[i].value) {
        animations.push(
          this.animateDigit(this.digitEls[i], newText[i], duration),
        );
      }
    }

    if (animations.length === 0) {
      this.animating = false;
      this.drain();
      return;
    }

    this.pulse();

    if (this.prefersReducedMotion) {
      this.span.setAttribute("aria-label", newText);
      this.span.dataset.count = count;
      this.animating = false;
      if (this.queue.length === 0) this.tickDuration = null;
      this.drain();
      return;
    }

    Promise.all(animations).then(() => {
      this.span.setAttribute("aria-label", newText);
      this.span.dataset.count = count;
      this.animating = false;
      if (this.queue.length === 0) this.tickDuration = null;
      this.drain();
    });
  }

  animateDigit(digitObj, newValue, duration) {
    if (this.prefersReducedMotion) {
      digitObj.inner.textContent = newValue;
      digitObj.value = newValue;
      return Promise.resolve();
    }

    return new Promise((resolve) => {
      const oldInner = digitObj.inner;
      oldInner.classList.add("rsvp-counter__digit-inner--exiting");
      oldInner.style.animationDuration = `${duration}ms`;

      const newInner = document.createElement("span");
      newInner.className =
        "rsvp-counter__digit-inner rsvp-counter__digit-inner--entering";
      newInner.textContent = newValue;
      newInner.style.animationDuration = `${duration}ms`;
      digitObj.wrapper.appendChild(newInner);

      newInner.addEventListener(
        "animationend",
        () => {
          oldInner.remove();
          newInner.classList.remove("rsvp-counter__digit-inner--entering");
          newInner.style.animationDuration = "";
          digitObj.inner = newInner;
          digitObj.value = newValue;
          resolve();
        },
        { once: true },
      );
    });
  }

  drain() {
    if (this.queue.length > 0) {
      this.animateToCount(this.queue.shift());
    }
  }

  pulse() {
    this.span.classList.remove("rsvp-counter--tick");
    void this.span.offsetWidth;
    this.span.classList.add("rsvp-counter--tick");
  }
}
