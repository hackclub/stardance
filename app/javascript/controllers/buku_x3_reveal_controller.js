import { Controller } from "@hotwired/stimulus";

const BODY_OPEN_CLASS = "buku-x3-reveal-open";
const ROLE_DELAY_MS = 2100;
const FINISH_DELAY_MS = 5800;
const REMOVE_DELAY_MS = 420;

export default class extends Controller {
  static targets = ["skip", "art"];
  static values = { dismissThing: String, animationUrl: String };

  connect() {
    this.finished = false;
    this.started = false;
    this.timers = [];
    this.previousFocus = document.activeElement;
    this.reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;

    // Native modality makes the page underneath inert and keeps keyboard
    // focus inside the reveal, including while it fades out.
    this.element.showModal();
    document.body.classList.add(BODY_OPEN_CLASS);
    this.element.classList.add("buku-x3-reveal--ready");
    this.skipTarget.focus({ preventScroll: true });

    if (this.reduceMotion) {
      this.start();
      return;
    }

    // Wait for the artwork, but never trap someone behind a slow image.
    this.preload = new Image();
    this.preload.onload = () => this.start(true);
    this.preload.onerror = () => this.start();
    this.preload.src = this.animationUrlValue;
    this.timers.push(setTimeout(() => this.start(), 4000));
  }

  disconnect() {
    this.cleanup();
  }

  start(animated = false) {
    if (this.started || this.finished || !this.element.isConnected) return;
    this.started = true;
    if (animated) this.artTarget.src = this.animationUrlValue;
    this.element.classList.add("buku-x3-reveal--signal");

    if (this.reduceMotion) {
      this.element.classList.add("buku-x3-reveal--role");
      // Keep the static version open so it can be read at leisure.
      return;
    }

    this.timers.push(
      setTimeout(() => {
        this.element.classList.add("buku-x3-reveal--role");
      }, ROLE_DELAY_MS),
      setTimeout(() => this.finish(), FINISH_DELAY_MS),
    );
  }

  cancel(event) {
    event.preventDefault();
    this.finish();
  }

  beforeCache() {
    this.finish();
    this.cleanup();
    this.element.remove();
  }

  finish() {
    if (this.finished) return;

    this.finished = true;
    this._recordDismissal();
    this.element.classList.add("buku-x3-reveal--leaving");
    this.timers.push(
      setTimeout(
        () => {
          this.cleanup();
          this.element.remove();
        },
        this.reduceMotion ? 0 : REMOVE_DELAY_MS,
      ),
    );
  }

  cleanup() {
    this.timers.forEach((timer) => clearTimeout(timer));
    if (this.preload) {
      this.preload.onload = null;
      this.preload.onerror = null;
    }
    this.element.close();
    document.body.classList.remove(BODY_OPEN_CLASS);
    if (this.previousFocus?.isConnected) {
      this.previousFocus.focus({ preventScroll: true });
    }
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
      keepalive: true,
    }).catch(() => {});
  }
}
