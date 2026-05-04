import { Controller } from "@hotwired/stimulus";

// Auto-scrolls the project thumbnails carousel on mobile (≤900px) and
// supports user drag/swipe. Items are rendered twice in the track; once the
// user (or auto-scroll) crosses the half-way mark we subtract the half-width
// so the loop is visually seamless. Reduces motion → no auto-scroll.
export default class extends Controller {
  static targets = ["track"];
  static values = { speed: { type: Number, default: 30 } }; // px / sec

  connect() {
    this._mq = window.matchMedia("(max-width: 900px)");
    this._reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    this._onMq = () => this._sync();
    this._mq.addEventListener("change", this._onMq);
    this._reduceMotion.addEventListener("change", this._onMq);
    this._userScrolling = false;
    this._userEndTimer = null;
    this._onUserStart = () => {
      this._userScrolling = true;
      clearTimeout(this._userEndTimer);
    };
    this._onUserEnd = () => {
      clearTimeout(this._userEndTimer);
      // Brief pause after the user stops touching so momentum scroll can
      // settle before we resume the auto-loop.
      this._userEndTimer = setTimeout(() => {
        this._userScrolling = false;
      }, 600);
    };
    this._onScroll = () => this._wrap();
    this.element.addEventListener("pointerdown", this._onUserStart, { passive: true });
    this.element.addEventListener("touchstart", this._onUserStart, { passive: true });
    this.element.addEventListener("wheel", this._onUserStart, { passive: true });
    this.element.addEventListener("pointerup", this._onUserEnd, { passive: true });
    this.element.addEventListener("pointercancel", this._onUserEnd, { passive: true });
    this.element.addEventListener("touchend", this._onUserEnd, { passive: true });
    this.element.addEventListener("touchcancel", this._onUserEnd, { passive: true });
    this.element.addEventListener("scroll", this._onScroll, { passive: true });
    this._observeItems();
    this._sync();
  }

  disconnect() {
    this._stop();
    this._mq.removeEventListener("change", this._onMq);
    this._reduceMotion.removeEventListener("change", this._onMq);
    this.element.removeEventListener("scroll", this._onScroll);
    this.element.removeEventListener("pointerdown", this._onUserStart);
    this.element.removeEventListener("touchstart", this._onUserStart);
    this.element.removeEventListener("wheel", this._onUserStart);
    this.element.removeEventListener("pointerup", this._onUserEnd);
    this.element.removeEventListener("pointercancel", this._onUserEnd);
    this.element.removeEventListener("touchend", this._onUserEnd);
    this.element.removeEventListener("touchcancel", this._onUserEnd);
    if (this._observer) this._observer.disconnect();
  }

  _observeItems() {
    if (typeof IntersectionObserver === "undefined") return;
    this._observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          // Map intersectionRatio (0..1) to --in-view so the description
          // fades in proportionally as the card enters/leaves the row.
          entry.target.style.setProperty("--in-view", entry.intersectionRatio.toFixed(3));
        }
      },
      {
        root: this.element,
        // Many thresholds → smooth opacity ramp during horizontal scroll.
        threshold: Array.from({ length: 11 }, (_, i) => i / 10),
      }
    );
    this.element.querySelectorAll(".project-thumbs__item").forEach((el) => {
      this._observer.observe(el);
    });
  }

  _sync() {
    if (this._mq.matches && !this._reduceMotion.matches) {
      this._start();
    } else {
      this._stop();
      this.element.scrollLeft = 0;
    }
  }

  _start() {
    if (this._raf) return;
    this._lastT = null;
    // scrollLeft can quantize to integer pixels, so we accumulate a float
    // offset and only commit when it advances at least 1px.
    this._offset = this.element.scrollLeft;
    const tick = (t) => {
      if (this._lastT == null) this._lastT = t;
      const dt = (t - this._lastT) / 1000;
      this._lastT = t;
      if (!this._userScrolling) {
        this._offset += this.speedValue * dt;
        if (Math.abs(this._offset - this.element.scrollLeft) >= 1) {
          this.element.scrollLeft = this._offset;
        }
        this._wrap();
      } else {
        // Resync float offset if user is dragging.
        this._offset = this.element.scrollLeft;
      }
      this._raf = requestAnimationFrame(tick);
    };
    this._raf = requestAnimationFrame(tick);
  }

  _stop() {
    if (this._raf) cancelAnimationFrame(this._raf);
    this._raf = null;
  }

  _wrap() {
    // Track contains 2 passes; once we've scrolled past 1/2 of its content
    // width, jump back by that distance to keep the loop seamless.
    const track = this.hasTrackTarget ? this.trackTarget : this.element.firstElementChild;
    if (!track) return;
    const half = track.scrollWidth / 2;
    if (half <= 0) return;
    if (this.element.scrollLeft >= half) {
      this.element.scrollLeft -= half;
      if (this._offset != null) this._offset -= half;
    } else if (this.element.scrollLeft < 0) {
      this.element.scrollLeft += half;
      if (this._offset != null) this._offset += half;
    }
  }
}
