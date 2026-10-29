import { Controller } from "@hotwired/stimulus";
import { serverClock } from "../lib/server_clock.js";

const DISMISSAL = "stardance_finale";
const COUNTDOWN_MS = 3000;

export default class extends Controller {
  static values = {
    endsAt: String,
    seen: Boolean,
    viewerId: String,
    previewEnabled: Boolean,
    dismissUrl: String,
  };
  static targets = [
    "dialog",
    "panel",
    "video",
    "play",
    "status",
    "continue",
    "previewReset",
  ];

  connect() {
    this.phase = "idle";
    this.beforeCache = () => {
      clearInterval(this.timer);
      this.unsubscribeClock?.();
      this.cleanup({ restore: false });
    };
    document.addEventListener("turbo:before-cache", this.beforeCache);
    this.unsubscribeClock = serverClock.subscribe(() => this.tick());
    this.timer = setInterval(() => this.tick(), 100);
    this.tick();
  }

  disconnect() {
    this.unsubscribeClock?.();
    clearInterval(this.timer);
    document.removeEventListener("turbo:before-cache", this.beforeCache);
    this.cleanup({ restore: false });
  }

  get storageKey() {
    return `${DISMISSAL}:${this.viewerIdValue}`;
  }

  alreadySeen() {
    if (this.seenValue) return true;
    try {
      return localStorage.getItem(this.storageKey) === "seen";
    } catch {
      return false;
    }
  }

  tick(now = serverClock.now()) {
    if (document.hidden || !Number.isFinite(now)) return;
    if (this.phase === "idle") {
      const deadline = Date.parse(this.endsAtValue);
      if (
        !Number.isFinite(deadline) ||
        now < deadline - COUNTDOWN_MS ||
        this.alreadySeen()
      )
        return;
      // Let an active story finish; an unseen team reveal does not block this.
      if (document.querySelector(".visual-novel, .buku-x3-reveal")) return;
      this.start(now, false, now < deadline ? deadline : now + COUNTDOWN_MS);
    }
    if (this.phase !== "countdown") return;
    const seconds = Math.max(0, Math.ceil((this.countdownEndsAt - now) / 1000));
    if (seconds === 0) {
      if (this.previewing) this.beginDisintegration();
      else this.confirmFinale();
    }
  }

  beginDisintegration() {
    this.phase = "disintegrating";
    this.dialogTarget.showModal();
    this.dispatch("disintegrate");
  }

  async confirmFinale() {
    if (this.checkingEnd || performance.now() < (this.nextEndCheck || 0))
      return;
    this.checkingEnd = true;
    try {
      const result = await serverClock.sync();
      if (
        this.phase === "countdown" &&
        !this.previewing &&
        !document.hidden &&
        result?.ended
      ) {
        this.beginDisintegration();
      }
    } finally {
      this.checkingEnd = false;
      this.nextEndCheck = performance.now() + 1000;
    }
  }

  start(now, preview, deadline = now + COUNTDOWN_MS) {
    this.previewing = preview;
    this.previewResetTarget.hidden = !preview;
    this.previousFocus = document.activeElement;
    this.phase = "countdown";
    this.countdownEndsAt = deadline;
    this.originalClocks = new Map();
    document
      .querySelectorAll(".buku-x3-status [data-countdown-reset-at-value]")
      .forEach((clock) => {
        this.originalClocks.set(
          clock,
          clock.getAttribute("data-countdown-reset-at-value"),
        );
        clock.setAttribute(
          "data-countdown-reset-at-value",
          new Date(deadline).toISOString(),
        );
      });
    this.panelTarget.hidden = true;
    if (this.hasStatusTarget) this.statusTarget.textContent = "";
    if (this.hasContinueTarget) this.continueTarget.disabled = false;
  }

  async preview() {
    if (!this.previewEnabledValue) return;
    if (!Number.isFinite(serverClock.now())) await serverClock.sync();
    const now = serverClock.now();
    if (!Number.isFinite(now)) return;
    this.cleanup();
    this.start(now, true);
  }

  resetPreview() {
    if (!this.previewEnabledValue || !this.previewing) return;
    this.cleanup();
  }

  showVideo() {
    if (this.phase !== "disintegrating") return;
    this.phase = "video";
    this.panelTarget.hidden = false;
    if (this.hasVideoTarget) {
      this.continueTarget.focus();
      this.videoTarget.currentTime = 0;
      this.playVideo();
    } else {
      this.previewResetTarget.hidden = true;
      this.finish({ keepBlank: true });
    }
  }

  async playVideo() {
    this.playTarget.hidden = true;
    try {
      await this.videoTarget.play();
    } catch {
      if (this.phase !== "video") return;
      this.playTarget.hidden = false;
      this.statusTarget.textContent = "Press play to watch the finale.";
      this.playTarget.focus();
    }
  }

  videoError() {
    this.playTarget.hidden = false;
    this.statusTarget.textContent =
      "The video couldn’t load. Try play again, or continue.";
  }

  async finish({ keepBlank = false } = {}) {
    if (this.phase !== "video" || this.saving) return;
    this.saving = true;
    if (this.hasContinueTarget) this.continueTarget.disabled = true;
    try {
      if (!this.previewing) {
        const token = document.querySelector(
          "meta[name='csrf-token']",
        )?.content;
        const response = await fetch(this.dismissUrlValue, {
          method: "POST",
          credentials: "same-origin",
          keepalive: true,
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": token || "",
          },
          body: JSON.stringify({ thing_name: DISMISSAL }),
        });
        if (!response.ok) throw new Error("Could not save completion");
        this.seenValue = true;
        try {
          localStorage.setItem(this.storageKey, "seen");
        } catch {
          /* Server state is authoritative on the next visit. */
        }
      }
      if (keepBlank) this.phase = "complete";
      else this.cleanup();
    } catch {
      if (this.hasStatusTarget) {
        this.statusTarget.textContent =
          "Couldn’t save your progress. Please try continue again.";
      }
      if (this.hasContinueTarget) this.continueTarget.disabled = false;
    } finally {
      this.saving = false;
    }
  }

  preventClose(event) {
    event.preventDefault();
  }

  cleanup({ restore = true } = {}) {
    if (this.hasVideoTarget) this.videoTarget.pause();
    this.dialogTarget.close();
    this.originalClocks?.forEach((deadline, clock) =>
      clock.setAttribute("data-countdown-reset-at-value", deadline),
    );
    this.originalClocks?.clear();
    if (restore && this.phase !== "idle") this.dispatch("reset");
    this.phase = "idle";
    this.previewing = false;
    if (this.previousFocus?.isConnected)
      this.previousFocus.focus({ preventScroll: true });
  }
}
