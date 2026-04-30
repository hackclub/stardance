import { Controller } from "@hotwired/stimulus";

// Starts all project thumbnails aligned at the top, then eases them
// into their staggered positions as the section scrolls into view.
export default class extends Controller {
  static targets = ["item"];

  // Final margin-top offsets (px) for items 1-5
  static OFFSETS = [-28, 34, -14, 42, -8];

  connect() {
    this._onScroll = this._update.bind(this);
    window.addEventListener("scroll", this._onScroll, { passive: true });
    this._update();
  }

  disconnect() {
    window.removeEventListener("scroll", this._onScroll);
  }

  _update() {
    const rect = this.element.getBoundingClientRect();
    const windowH = window.innerHeight;

    // Dead zone: nothing happens until the section top is 80% from the
    // top of the viewport (i.e. you've scrolled past it a little).
    // Then we accumulate scroll-pixels that drive all items at the same
    // speed — each item simply caps at its own final offset.
    const deadZone = windowH * 0.65; // section top must reach here first
    const scrolledPast = deadZone - rect.top; // px scrolled past dead zone
    const px = Math.max(0, scrolledPast * 0.5); // 0.5x scroll speed

    const maxOffset = Math.max(...this.constructor.OFFSETS);

    this.itemTargets.forEach((el, i) => {
      const offset = this.constructor.OFFSETS[i] || 0;
      // All items move 1:1 with scroll, but each caps at its own offset
      el.style.marginTop = `${Math.min(px, offset)}px`;
    });
  }
}
