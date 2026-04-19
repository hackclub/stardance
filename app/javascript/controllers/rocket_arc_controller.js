import { Controller } from "@hotwired/stimulus";

// Animates a rocket along a quadratic bezier arc as the user scrolls
// through the footer section — from the yellow creature to the purple creature.
export default class extends Controller {
  static targets = ["rocket", "star"];

  connect() {
    this.handleScroll = this.handleScroll.bind(this);
    window.addEventListener("scroll", this.handleScroll, { passive: true });
    this.handleScroll();
  }

  disconnect() {
    window.removeEventListener("scroll", this.handleScroll);
  }

  // Get the center of an element as a % of the footer's dimensions
  centerOf(el) {
    const footerRect = this.element.getBoundingClientRect();
    const elRect = el.getBoundingClientRect();
    return {
      x:
        ((elRect.left + elRect.width / 2 - footerRect.left) /
          footerRect.width) *
        100,
      y:
        ((elRect.top + elRect.height / 2 - footerRect.top) /
          footerRect.height) *
        100,
    };
  }

  handleScroll() {
    const rect = this.element.getBoundingClientRect();
    const vh = window.innerHeight;

    const scrollStart = vh - rect.top;
    const scrollEnd = vh - rect.top - rect.height;
    const progress = scrollStart / rect.height;

    const rocket = this.rocketTarget;

    // Don't show until scrolled 20% into the footer, hide when fully past
    if (progress < 0.2 || scrollEnd >= vh) {
      rocket.style.opacity = 0;
      return;
    }

    // Remap 0.2–1.0 → 0–0.8
    const t = Math.min(0.8, ((progress - 0.2) / 0.8) * 0.8);

    // Derive start/end from the two star targets if available,
    // otherwise fall back to hardcoded positions.
    // Start at purple (top-right), end at yellow (bottom-left) as user scrolls down.
    let p0, p2;
    if (this.starTargets.length >= 2) {
      // starTargets[0] = footer4 (yellow star), starTargets[1] = footer1 (purple star)
      const yellow = this.centerOf(this.starTargets[0]);
      const purple = this.centerOf(this.starTargets[1]);
      p0 = { x: purple.x + 5, y: purple.y - 10 }; // start at purple, nudged up and right
      p2 = { x: yellow.x + 1, y: yellow.y - 5 }; // end at yellow, nudged tiny right and slightly up
    } else {
      p0 = { x: 72, y: 38 };
      p2 = { x: 5, y: 78 };
    }

    // Control point — midpoint horizontally, arcing above both stars
    const p1 = {
      x: (p0.x + p2.x) / 2,
      y: Math.min(p0.y, p2.y) - 10,
    };

    const mt = 1 - t;
    const x = mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x;
    const y = mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y;

    // Tangent for rotation (rocket points along the curve)
    const dx = 2 * mt * (p1.x - p0.x) + 2 * t * (p2.x - p1.x);
    const dy = 2 * mt * (p1.y - p0.y) + 2 * t * (p2.y - p1.y);
    const angle = Math.atan2(dy, dx) * (180 / Math.PI);

    rocket.style.left = `${x}%`;
    rocket.style.top = `${y}%`;
    rocket.style.transform = `translate(-50%, -50%) rotate(${angle}deg)`;
    rocket.style.opacity = 1;

    // Parallax: stars drift upward slightly as user scrolls down
    this.starTargets.forEach((star) => {
      const drift = -t * 55;
      star.style.transform = `translateY(${drift}px)`;
    });
  }
}
