import { Controller } from "@hotwired/stimulus";

// Long leaderboard names fade out instead of clipping. Hovering the right half
// of a cut-off name scrolls it to its end so the whole name can be read, and
// moving back to the left half (or leaving) scrolls it back. Touch screens can
// swipe the name sideways. The fades follow the scroll position.
export default class extends Controller {
  connect() {
    this.end = false;
    this.update = this.update.bind(this);
    this.observer = new ResizeObserver(this.update);
    this.observer.observe(this.element);
    this.element.addEventListener("scroll", this.update, { passive: true });
    this.update();
  }

  disconnect() {
    this.observer?.disconnect();
    this.element.removeEventListener("scroll", this.update);
  }

  get overflow() {
    return this.element.scrollWidth - this.element.clientWidth;
  }

  update() {
    const { scrollLeft } = this.element;
    const { classList } = this.element;
    classList.toggle("buku-leaderboard__name--fade-start", scrollLeft > 1);
    classList.toggle(
      "buku-leaderboard__name--fade-end",
      this.overflow > 1 && scrollLeft < this.overflow - 1,
    );
  }

  track(event) {
    if (this.overflow <= 1) return;
    const { left, width } = this.element.getBoundingClientRect();
    this.scrollTo(event.clientX - left > width / 2);
  }

  // Keyboard focus has no pointer position, so show the end of the name.
  reveal() {
    if (this.overflow > 1) this.scrollTo(true);
  }

  reset() {
    this.scrollTo(false);
  }

  scrollTo(end) {
    // mousemove fires constantly; restarting a smooth scroll on every event
    // would stall it, so only scroll when the target end changes.
    if (end === this.end) return;
    this.end = end;
    const reduce = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    this.element.scrollTo({
      left: end ? this.overflow : 0,
      behavior: reduce ? "auto" : "smooth",
    });
  }
}
