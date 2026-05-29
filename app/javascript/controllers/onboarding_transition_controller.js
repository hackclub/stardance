import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    duration: { type: Number, default: 700 },
    autoAdvanceDelay: { type: Number, default: 0 },
    autoAdvanceHref: { type: String, default: "" },
  };

  connect() {
    this.onSubmitStart = (event) => {
      if (!this.element.contains(event.target)) return;
      this.element.classList.add("is-leaving");
    };

    document.addEventListener("turbo:submit-start", this.onSubmitStart);

    if (this.autoAdvanceDelayValue > 0 && this.autoAdvanceHrefValue) {
      this.autoAdvanceTimer = setTimeout(() => {
        this._autoAdvance(this.autoAdvanceHrefValue);
      }, this.autoAdvanceDelayValue);

      this.skipClickHandler = (event) => {
        if (event.target.closest("a, button, input, label, [role=button]"))
          return;
        if (this.element.classList.contains("is-leaving")) return;
        if (this.autoAdvanceTimer) {
          clearTimeout(this.autoAdvanceTimer);
          this.autoAdvanceTimer = null;
        }
        this._autoAdvance(this.autoAdvanceHrefValue);
      };
      this.element.addEventListener("click", this.skipClickHandler);
    }
  }

  disconnect() {
    document.removeEventListener("turbo:submit-start", this.onSubmitStart);
    if (this.autoAdvanceTimer) clearTimeout(this.autoAdvanceTimer);
    if (this.skipClickHandler) {
      this.element.removeEventListener("click", this.skipClickHandler);
    }
  }

  _autoAdvance(href) {
    // Pin the screen + moon at their currently-animated opacity so the
    // fade-out keyframes interpolate from the visible state instead of
    // snapping back to the underlying default of 1.
    const planet = this.element.querySelector(".onboarding-welcome__planet");
    this.element.style.opacity = getComputedStyle(this.element).opacity;
    if (planet) planet.style.opacity = getComputedStyle(planet).opacity;
    void this.element.offsetHeight;

    this.element.classList.add("is-leaving");
    this._holdNextRender(this.durationValue);
    if (window.Turbo) {
      window.Turbo.visit(href);
    } else {
      setTimeout(() => {
        window.location.href = href;
      }, this.durationValue);
    }
  }

  leave(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button === 1)
      return;
    event.preventDefault();
    const target = event.currentTarget;
    const href =
      target.getAttribute("href") || target.getAttribute("data-href");
    if (!href) return;

    this.element.classList.add("is-leaving");

    // Start the visit immediately — the page swap will be held back below
    // until the fade-out animation has had its full duration.
    this._holdNextRender(this.durationValue);
    if (window.Turbo) {
      window.Turbo.visit(href);
    } else {
      // No Turbo available — fall back to waiting then full nav.
      setTimeout(() => {
        window.location.href = href;
      }, this.durationValue);
    }
  }

  press(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const form = button.form || button.closest("form");
    if (!form) return;

    const siblings = Array.from(
      form.querySelectorAll("button[type=submit]"),
    ).filter((b) => b !== button);

    let totalDelay;

    if (siblings.length > 0) {
      // Multi-option: fade siblings, brief hold, then fade selected + page
      const OTHERS_OUT = 350;
      const HOLD = 250;
      const SELECTED_OUT = 650;

      siblings.forEach((s) => s.classList.add("is-fading-out"));

      setTimeout(() => {
        button.classList.add("is-fading-out");
        this.element.classList.add("is-leaving");
      }, OTHERS_OUT + HOLD);

      totalDelay = OTHERS_OUT + HOLD + SELECTED_OUT;
    } else {
      // Solo button: just fade the page out
      this.element.classList.add("is-leaving");
      totalDelay = 650;
    }

    // Submit immediately so the network request runs alongside the
    // animation, then hold the page swap until the animation finishes.
    this._holdNextRender(totalDelay);
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit(button);
    } else {
      form.submit();
    }
  }

  // Suspend the next Turbo render until the animation has had `ms` to play.
  // Uses turbo:before-render to pause the body swap; resumes after the
  // elapsed time even if the network response came back earlier.
  _holdNextRender(ms) {
    const start = performance.now();
    const handler = (event) => {
      document.removeEventListener("turbo:before-render", handler);
      const remaining = ms - (performance.now() - start);
      if (remaining <= 0 || !event.detail || !event.detail.resume) return;
      event.preventDefault();
      setTimeout(() => event.detail.resume(), remaining);
    };
    document.addEventListener("turbo:before-render", handler, { once: true });
  }
}
