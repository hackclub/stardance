import { Controller } from "@hotwired/stimulus";

// Adds a gentle rise+fade to section titles and body content as they enter
// the viewport. One-shot per element (unobserves after reveal). Skips the
// hero — that has its own warp-in choreography.
//
// Targets are auto-collected by CSS selector so section ERB files stay clean.
// Any element within the controller's scope matching `REVEAL_SELECTORS` is
// prepped with `.reveal` and revealed when it intersects.
const REVEAL_SELECTORS = [
  ".heres-how__title",
  ".heres-how__repeat",
  ".prizes__text",
  ".what-is-this__title",
  ".what-is-this__body",
  ".done-before__title",
  ".done-before__subtitle",
  ".done-before__cards",
  ".faq-section__title",
  ".faq-section__list",
  ".cta-section__title",
  ".cta-section__subtitle",
  ".cta-section__form",
];

export default class extends Controller {
  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    if (typeof IntersectionObserver === "undefined") return;

    const targets = this.element.querySelectorAll(REVEAL_SELECTORS.join(","));
    if (targets.length === 0) return;

    for (const el of targets) el.classList.add("reveal");

    this.io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-revealed");
            this.io.unobserve(entry.target);
          }
        }
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );

    for (const el of targets) this.io.observe(el);
  }

  disconnect() {
    this.io?.disconnect();
  }
}
