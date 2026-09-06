import { Controller } from "@hotwired/stimulus";

// Drives the visual-novel intro scene (:bukux2). Reveals one line at a time
// with a typewriter effect; advancing mid-line finishes the reveal instead of
// skipping ahead, the way a visual novel does. Finishing records a per-account
// dismissal so the scene only plays once.
const REVEAL_MS = 22;
const BODY_OPEN_CLASS = "visual-novel-open";
// Runs Vega's idle sprite animation. Held while a line types itself out, so
// his cycle restarts with every new line and he rests in between.
const SPEAKING_CLASS = "visual-novel--speaking";

export default class extends Controller {
  static targets = ["line", "dot", "advance"];
  static values = { lines: Array, dismissThing: String };

  connect() {
    this.index = 0;
    this.reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;

    this._onKey = this._onKey.bind(this);
    document.addEventListener("keydown", this._onKey);

    this._previousOverflow = document.body.style.overflow;
    document.body.classList.add(BODY_OPEN_CLASS);

    // Timer rather than rAF: a backgrounded tab never paints, and the scene
    // must not sit invisible-but-open while it holds the scroll lock.
    setTimeout(() => this.element.classList.add("visual-novel--ready"), 0);
    this.advanceTarget.focus({ preventScroll: true });
    this._reveal();
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey);
    document.body.classList.remove(BODY_OPEN_CLASS);
    document.body.style.overflow = this._previousOverflow || "";
    this._stopReveal();
  }

  // Click / space / arrow: finish the current line if it's still typing,
  // otherwise move to the next one (or close on the last).
  advance() {
    if (this._revealing) {
      this._finishReveal();
      return;
    }

    if (this.index >= this.linesValue.length - 1) {
      this.finish();
      return;
    }

    this.index += 1;
    this._syncProgress();
    this._reveal();
  }

  finish() {
    this._stopReveal();
    this._recordDismissal();

    this.element.classList.remove("visual-novel--ready");
    this.element.addEventListener(
      "transitionend",
      () => this.element.remove(),
      {
        once: true,
      },
    );
    // Belt and braces: drop the scene even if the fade-out never fires.
    setTimeout(() => this.element.remove(), 600);
  }

  _onKey(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.finish();
    } else if ([" ", "Enter", "ArrowRight"].includes(event.key)) {
      event.preventDefault();
      this.advance();
    }
  }

  // Typed out on a rAF clock rather than a timer, so a backgrounded tab pauses
  // the reveal instead of trickling it out at the throttled timer rate.
  _reveal() {
    const line = this.linesValue[this.index] || "";
    this._stopReveal();
    this._syncAdvanceLabel();

    if (this.reduceMotion) {
      this.lineTarget.textContent = line;
      return;
    }

    this._revealing = true;
    this.element.classList.add(SPEAKING_CLASS);
    this.lineTarget.textContent = "";
    const startedAt = performance.now();

    const step = (now) => {
      const revealed = Math.floor((now - startedAt) / REVEAL_MS);
      this.lineTarget.textContent = line.slice(0, revealed);

      if (revealed >= line.length) {
        this._finishReveal();
      } else {
        this._revealFrame = requestAnimationFrame(step);
      }
    };

    this._revealFrame = requestAnimationFrame(step);
  }

  _finishReveal() {
    this.lineTarget.textContent = this.linesValue[this.index] || "";
    this._stopReveal();
  }

  _stopReveal() {
    if (this._revealFrame) cancelAnimationFrame(this._revealFrame);
    this._revealFrame = null;
    this._revealing = false;
    this.element.classList.remove(SPEAKING_CLASS);
  }

  _syncProgress() {
    this.dotTargets.forEach((dot, index) => {
      dot.classList.toggle("visual-novel__dot--active", index <= this.index);
    });
  }

  _syncAdvanceLabel() {
    const last = this.index >= this.linesValue.length - 1;
    this.advanceTarget.setAttribute("aria-label", last ? "Close" : "Next line");
    this.element.classList.toggle("visual-novel--final", last);
  }

  _recordDismissal() {
    if (!this.dismissThingValue) return;

    const token = document.querySelector("meta[name='csrf-token']")?.content;
    fetch("/my/dismissals", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token || "",
      },
      body: JSON.stringify({ thing_name: this.dismissThingValue }),
    }).catch(() => {});
  }
}
