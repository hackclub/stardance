import { Controller } from "@hotwired/stimulus";

// The word and sticker change together every few seconds, and faster while hovered.
const IDLE_MS = 2200;
const HOVER_MS = 700;
// Matches the height of a word in the rolling track.
const WORD_HEIGHT = 32;
// The track holds a copy of the first word at the end, so it rolls on to it and then snaps back.
const SNAP_MS = 460;

export default class extends Controller {
  static targets = ["track", "sticker"];

  connect() {
    this.reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    this.index = 0;
    this.interval = IDLE_MS;

    this.onVisibility = () => this.sync();
    document.addEventListener("visibilitychange", this.onVisibility);

    this.observer = new IntersectionObserver(
      ([entry]) => {
        this.visible = entry.isIntersecting;
        this.sync();
      },
      { rootMargin: "120px" },
    );
    this.observer.observe(this.element);
  }

  disconnect() {
    this.observer?.disconnect();
    document.removeEventListener("visibilitychange", this.onVisibility);
    this.stop();
    clearTimeout(this.snapTimer);
  }

  speedUp() {
    this.interval = HOVER_MS;
    this.sync(true);
  }

  slowDown() {
    this.interval = IDLE_MS;
    this.sync(true);
  }

  sync(restart = false) {
    if (this.reduceMotion) return;
    const shouldRun = this.visible && !document.hidden;
    if (restart || !shouldRun) this.stop();
    if (shouldRun && !this.timer) {
      this.timer = setInterval(() => this.advance(), this.interval);
    }
  }

  stop() {
    clearInterval(this.timer);
    this.timer = null;
  }

  advance() {
    const count = this.stickerTargets.length;
    this.index += 1;
    this.trackTarget.style.transition = "";
    this.trackTarget.style.transform = `translateY(${-WORD_HEIGHT * this.index}px)`;
    if (this.index === count) {
      this.index = 0;
      clearTimeout(this.snapTimer);
      this.snapTimer = setTimeout(() => {
        this.trackTarget.style.transition = "none";
        this.trackTarget.style.transform = "translateY(0)";
      }, SNAP_MS);
    }
    this.stickerTargets.forEach((sticker, i) =>
      sticker.classList.toggle(
        "savepoint-promo__sticker--active",
        i === this.index,
      ),
    );
  }
}
