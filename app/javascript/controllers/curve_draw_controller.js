import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["path"];
  static values = { startAfter: String };

  connect() {
    this.onScroll = this.onScroll.bind(this);

    const path = this.pathTarget;
    this.totalLength = path.getTotalLength();

    path.style.strokeDasharray = this.totalLength;
    path.style.strokeDashoffset = this.totalLength;

    window.addEventListener("scroll", this.onScroll, { passive: true });
    this.onScroll();
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll);
  }

  onScroll() {
    const rect = this.element.getBoundingClientRect();
    const vh = window.innerHeight;

    if (this.hasStartAfterValue && this.startAfterValue) {
      const prev = document.querySelector(this.startAfterValue);
      if (prev) {
        const prevBottom = prev.getBoundingClientRect().bottom;
        if (prevBottom > 0) {
          console.log("i'm here")
          this.pathTarget.style.strokeDashoffset = this.totalLength;
          this._startBottom = null;
          return;
        }

        if (this._startBottom == null) {
          this._startBottom = rect.bottom;
        }
        const progress = Math.max(0, Math.min(1, 1 - rect.bottom / this._startBottom));
        this.pathTarget.style.strokeDashoffset = this.totalLength * (1 - progress);
        return;
      }
    }

    const scrolledIn = vh - rect.top;
    const totalRange = rect.height + vh;
    const progress = Math.max(0, Math.min(1, scrolledIn / totalRange));

    this.pathTarget.style.strokeDashoffset = this.totalLength * (1 - progress);
  }
}
