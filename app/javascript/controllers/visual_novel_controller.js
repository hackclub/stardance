import { Controller } from "@hotwired/stimulus";

// Drives the rocket and buku intro scenes. Reveals one line at a time
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
  static values = {
    lines: Array,
    shakeLines: Array,
    dismissThing: String,
    nextSceneUrl: String,
    nextLabel: { type: String, default: "Next line" },
    closeLabel: { type: String, default: "Close" },
  };

  connect() {
    this.index = 0;
    this.finishing = false;
    this.request = new AbortController();
    this.previousFocus = document.activeElement;
    this.reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;

    this._onKey = this._onKey.bind(this);
    document.addEventListener("keydown", this._onKey);

    this._previousOverflow = document.body.style.overflow;
    document.body.classList.add(BODY_OPEN_CLASS);

    // Timer rather than rAF: a backgrounded tab never paints, and the scene
    // must not sit invisible-but-open while it holds the scroll lock.
    this.readyTimer = setTimeout(
      () => this.element.classList.add("visual-novel--ready"),
      0,
    );
    this.advanceTarget.focus({ preventScroll: true });
    this._reveal();
  }

  disconnect() {
    this.shakeAnimation?.cancel();
    this.request.abort();
    clearTimeout(this.readyTimer);
    clearTimeout(this.finishTimer);
    clearTimeout(this.requestTimer);
    document.removeEventListener("keydown", this._onKey);
    document.body.classList.remove(BODY_OPEN_CLASS);
    document.body.style.overflow = this._previousOverflow || "";
    this._stopReveal();
    if (this.previousFocus?.isConnected)
      this.previousFocus.focus({ preventScroll: true });
  }

  beforeCache() {
    this.request.abort();
    this.element.remove();
  }

  // Click / space / arrow: finish the current line if it's still typing,
  // otherwise move to the next one (or close on the last).
  advance() {
    if (this.finishing) return;
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

  async finish() {
    if (this.finishing) return;
    this.finishing = true;
    this.shakeAnimation?.cancel();
    this._stopReveal();
    let nextScene = null;
    // Only request the role after the server has saved intro completion.
    // Abort slow requests so a connection problem cannot trap the user here.
    this.requestTimer = setTimeout(() => this.request.abort(), 8000);
    try {
      const saved = await this._recordDismissal();
      if (saved && this.nextSceneUrlValue) {
        const response = await fetch(this.nextSceneUrlValue, {
          headers: { Accept: "text/html" },
          cache: "no-store",
          signal: this.request.signal,
        });
        if (response.ok) {
          const template = document.createElement("template");
          template.innerHTML = await response.text();
          nextScene = template.content.querySelector("dialog.buku-x3-reveal");
        }
      }
    } catch {
      // Failed dismissals replay the intro on the next load. If dismissal
      // succeeded, the next load renders the pending role reveal instead.
    } finally {
      clearTimeout(this.requestTimer);
    }
    if (!this.element.isConnected) return;
    document.removeEventListener("keydown", this._onKey);
    this.element.classList.remove("visual-novel--ready");
    this.finishTimer = setTimeout(
      () => {
        this.element.remove();
        if (nextScene && !document.querySelector("dialog.buku-x3-reveal")) {
          document.body.append(nextScene);
        }
      },
      this.reduceMotion ? 0 : 360,
    );
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
    this._shake();

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

  _shake() {
    this.shakeAnimation?.cancel();
    if (this.reduceMotion || !this.shakeLinesValue.includes(this.index)) return;

    // Shake the fixed scene itself, not the document root: transforming an
    // ancestor changes the containing block for fixed UI and can move the
    // dialogue offscreen on a scrolled page. Keep its opacity/layers intact.
    this.shakeAnimation = this.element.animate(
      [
        { translate: "0 0" },
        { translate: "-8px 4px" },
        { translate: "7px -5px" },
        { translate: "-6px -3px" },
        { translate: "5px 4px" },
        { translate: "-3px 2px" },
        { translate: "2px -1px" },
        { translate: "0 0" },
      ],
      { duration: 560, easing: "ease-out" },
    );
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
    this.advanceTarget.setAttribute(
      "aria-label",
      last ? this.closeLabelValue : this.nextLabelValue,
    );
    this.element.classList.toggle("visual-novel--final", last);
  }

  async _recordDismissal() {
    if (!this.dismissThingValue) return true;

    const token = document.querySelector("meta[name='csrf-token']")?.content;
    const response = await fetch("/my/dismissals", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token || "",
      },
      body: JSON.stringify({ thing_name: this.dismissThingValue }),
      signal: this.request.signal,
      keepalive: true,
    });
    return response.ok;
  }
}
