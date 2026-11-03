import { Controller } from "@hotwired/stimulus";
import { serverClock } from "../lib/server_clock.js";
import {
  finaleTimeline,
  canReplayFinale,
  DISINTEGRATION_MS,
  FADE_MS,
  COUNTDOWN_MS,
  REPLAY_COUNTDOWN_MS,
} from "../lib/stardance_finale_timeline.js";
import { YoutubeVideo } from "../lib/youtube_video.js";

const ARRIVAL_DISMISSAL = "stardance_finale_arrival_v1";

export default class extends Controller {
  static values = {
    endsAt: String,
    previewEnabled: Boolean,
    viewerId: String,
    arrivalSeen: Boolean,
  };
  static targets = [
    "dialog",
    "fade",
    "panel",
    "video",
    "play",
    "status",
    "previewReset",
    "countdown",
  ];

  initialize() {
    this.video = new YoutubeVideo(this.videoTarget);
  }

  connect() {
    this.phase = "idle";
    this.generation = 0;
    this.interaction = (event) => this.playOnArrival(event);
    document.addEventListener("click", this.interaction, true);
    document.addEventListener("keydown", this.interaction, true);
    this.beforeCache = () => {
      this.removeInteractionListeners();
      clearInterval(this.timer);
      this.unsubscribeClock?.();
      this.cleanup({ restore: false });
    };
    this.visibility = () => {
      if (document.hidden) this.video.pause();
    };
    document.addEventListener("turbo:before-cache", this.beforeCache);
    document.addEventListener("visibilitychange", this.visibility);
    this.unsubscribeClock = serverClock.subscribe(() => this.tick());
    this.timer = setInterval(() => this.tick(), 250);
    this.tick();
  }

  disconnect() {
    this.removeInteractionListeners();
    this.unsubscribeClock?.();
    clearInterval(this.timer);
    document.removeEventListener("turbo:before-cache", this.beforeCache);
    document.removeEventListener("visibilitychange", this.visibility);
    this.cleanup({ restore: false });
  }

  tick(now = serverClock.now()) {
    if (document.hidden || !Number.isFinite(now)) return;
    if (this.mode === "preview" || this.mode === "replay") {
      if (this.phase === "countdown" && this.hasCountdownTarget)
        this.countdownTarget.textContent = `stardance explodes in ${Math.max(0, Math.ceil((this.localDeadline - performance.now()) / 1000))}`;
      if (this.phase === "countdown" && performance.now() >= this.localDeadline)
        this.beginDisintegration();
      if (this.phase !== "video") this.updatePlayback();
      return;
    }
    const timeline = finaleTimeline(serverClock.data);
    if (!this.endsAtValue || !timeline) return;
    if (now >= timeline.finishesAt) {
      if (this.mode === "live") this.cleanup();
      else if (this.video.src) this.releaseVideo();
      return;
    }
    if (this.skipLive) return;
    // A small warm-up window; no media requests during ordinary site visits.
    if (
      timeline.ready &&
      now >= timeline.startsAt - 30000 &&
      !navigator.connection?.saveData
    )
      this.prepareVideo(timeline.videoId);
    if (now < timeline.startsAt - COUNTDOWN_MS) return;
    if (document.querySelector(".visual-novel, .buku-x3-reveal")) return;
    if (now >= timeline.startsAt && !serverClock.data?.ended) {
      this.confirmFinale();
      return;
    }
    if (this.phase === "idle") this.start("live", timeline);
    this.timeline = timeline;
    if (now < timeline.startsAt) return;
    if (now < timeline.revealAt - FADE_MS) {
      if (this.phase === "countdown")
        this.beginDisintegration(now - timeline.startsAt);
    } else if (now < timeline.revealAt) {
      if (this.phase === "countdown")
        this.beginDisintegration(DISINTEGRATION_MS);
      if (this.phase === "disintegrating")
        this.beginFade(timeline.revealAt - now);
    } else if (this.phase !== "video") {
      this.showVideo();
    }
    this.updatePlayback();
  }

  removeInteractionListeners() {
    document.removeEventListener("click", this.interaction, true);
    document.removeEventListener("keydown", this.interaction, true);
  }

  playOnArrival(event) {
    if (!event.isTrusted || this.arrivalSeenValue || this.phase !== "idle")
      return;
    if (event.type === "keydown" && !["Enter", " "].includes(event.key)) return;
    if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey)
      return;
    const timeline = finaleTimeline(serverClock.data);
    // Let the shared live show finish before offering the full catch-up sequence.
    if (!timeline?.ready || !(serverClock.now() >= timeline.finishesAt)) return;
    if (document.querySelector("dialog[open], .visual-novel, .buku-x3-reveal"))
      return;
    const key = `${ARRIVAL_DISMISSAL}:${this.viewerIdValue || "guest"}`;
    try {
      if (localStorage.getItem(key)) return;
    } catch {
      /* Playback still works when browser storage is unavailable. */
    }
    event.preventDefault();
    event.stopImmediatePropagation();
    this.replay();
    this.arrivalSeenValue = true;
    try {
      localStorage.setItem(key, "1");
    } catch {
      /* Keep the in-memory guard. */
    }
    if (this.viewerIdValue) {
      const token = document.querySelector("meta[name='csrf-token']")?.content;
      fetch("/my/dismissals", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token || "",
        },
        body: JSON.stringify({ thing_name: ARRIVAL_DISMISSAL }),
        keepalive: true,
      }).catch(() => {});
    }
  }

  async confirmFinale() {
    if (this.checkingEnd || performance.now() < (this.nextEndCheck || 0))
      return;
    this.checkingEnd = true;
    try {
      await serverClock.sync();
    } finally {
      this.checkingEnd = false;
      this.nextEndCheck = performance.now() + 1000;
    }
  }

  start(mode, timeline) {
    this.mode = mode;
    this.timeline = timeline;
    this.phase = "countdown";
    this.generation++;
    this.previousFocus = document.activeElement;
    this.previewResetTarget.hidden = mode !== "preview";
    this.panelTarget.hidden = true;
    this.statusTarget.textContent = "";
    this.playTarget.hidden = true;
    this.playBlocked = this.mediaFailed = this.mediaEnded = false;
    this.needsInitialSeek = true;
    this.video.muted = false;
    if (mode !== "live")
      this.startCountdown(
        mode === "replay" ? REPLAY_COUNTDOWN_MS : COUNTDOWN_MS,
      );
    if (timeline?.ready) this.prepareVideo(timeline.videoId);
  }

  async preview() {
    if (!this.previewEnabledValue) return;
    if (!Number.isFinite(serverClock.now())) await serverClock.sync();
    if (!Number.isFinite(serverClock.now())) return;
    this.cleanup();
    this.start("preview", finaleTimeline(serverClock.data));
  }

  startCountdown(durationMs) {
    this.localDeadline = performance.now() + durationMs;
    this.originalClocks = new Map();
    document
      .querySelectorAll("[data-stardance-countdown-override-at-value]")
      .forEach((clock) => {
        this.originalClocks.set(
          clock,
          clock.getAttribute("data-stardance-countdown-override-at-value"),
        );
        clock.setAttribute(
          "data-stardance-countdown-override-at-value",
          new Date(serverClock.now() + durationMs).toISOString(),
        );
      });
    if (this.hasCountdownTarget && this.originalClocks.size === 0) {
      this.countdownTarget.hidden = false;
      this.countdownTarget.textContent = `stardance explodes in ${durationMs / 1000}`;
      this.openDialog();
    }
  }

  replay() {
    const timeline = finaleTimeline(serverClock.data);
    if (!canReplayFinale(timeline, serverClock.now())) return;
    if (this.phase !== "idle") return;
    this.start("replay", timeline);
  }

  resetPreview() {
    if (this.previewEnabledValue && this.mode === "preview") this.cleanup();
  }

  beginDisintegration(elapsedMs = 0) {
    if (this.hasCountdownTarget) this.countdownTarget.hidden = true;
    this.phase = "disintegrating";
    this.openDialog();
    if (this.timeline?.ready) {
      this.panelTarget.classList.add("stardance-finale__panel--intro");
      this.panelTarget.hidden = false;
      this.videoReady();
    }
    // Only the local preview may use the simulator's duration override.
    const detail =
      this.mode === "preview"
        ? {}
        : { elapsedMs, durationMs: DISINTEGRATION_MS };
    this.dispatch("disintegrate", { detail });
  }

  fadeToBlack() {
    // Rendering performance never changes the shared live broadcast's timing.
    if (this.mode !== "live" && this.phase === "disintegrating")
      this.beginFade(FADE_MS);
  }

  async beginFade(remaining) {
    this.phase = "fading";
    const animation = this.fadeTarget.animate(
      [{ opacity: 1 - remaining / FADE_MS }, { opacity: 1 }],
      { duration: remaining, easing: "linear", fill: "forwards" },
    );
    this.fadeAnimation = animation;
    try {
      await animation.finished;
    } catch {
      return;
    }
    if (this.phase !== "fading" || this.fadeAnimation !== animation) return;
    if (this.mode === "live") this.tick();
    else this.showVideo();
  }

  showVideo() {
    if (!this.timeline?.ready || (this.mediaEnded && this.mode !== "live")) {
      this.finish();
      return;
    }
    this.phase = "video";
    this.openDialog();
    this.panelTarget.hidden = false;
    this.panelTarget.classList.remove("stardance-finale__panel--intro");
    this.dispatch("video");
    this.prepareVideo(this.timeline.videoId);
    if (this.video.readyState < 3)
      this.statusTarget.textContent = "loading the finale…";
    this.videoReady();
  }

  mediaActive() {
    return (
      this.timeline?.ready &&
      ["disintegrating", "fading", "video"].includes(this.phase)
    );
  }

  updatePlayback() {
    if (!this.mediaActive()) return;
    this.syncVideo();
    if (
      this.video.paused &&
      !this.playBlocked &&
      !this.mediaFailed &&
      !this.mediaEnded
    )
      this.attemptPlayback();
  }

  openDialog() {
    if (!this.dialogTarget.open) this.dialogTarget.showModal();
  }

  prepareVideo(videoId) {
    if (this.video.src === videoId) return;
    this.video.src = videoId;
    this.video.load();
  }

  videoReady() {
    if (!this.mediaActive()) return;
    this.syncVideo(true);
    if (!this.playBlocked && !this.mediaEnded) this.attemptPlayback();
  }

  syncVideo(force = false) {
    if (
      !this.mediaActive() ||
      (this.mode !== "live" &&
        this.phase === "video" &&
        !this.needsInitialSeek) ||
      this.mediaEnded ||
      this.video.readyState < 1
    )
      return;
    const now = this.mode === "live" ? serverClock.now() : performance.now();
    if (!Number.isFinite(now)) return;
    if (this.mode === "live" && now >= this.timeline.finishesAt) {
      this.finish();
      return;
    }
    const duration = this.video.duration;
    if (!Number.isFinite(duration) || duration <= 0) return;
    const target = Math.max(
      0,
      Math.min(
        (now -
          (this.mode === "live"
            ? this.timeline.startsAt
            : this.localDeadline)) /
          1000,
        duration - 0.05,
      ),
    );
    // Correct drift after buffering/sleep; don't continuously restart a slow seek.
    if (
      (force ||
        (!this.video.seeking && performance.now() >= (this.nextSeek || 0))) &&
      Math.abs(this.video.currentTime - target) > 1
    ) {
      this.video.currentTime = target;
      this.nextSeek = performance.now() + 2000;
    }
    this.needsInitialSeek = false;
  }

  async attemptPlayback() {
    if (this.playing || !this.mediaActive()) return;
    const generation = this.generation;
    this.playing = true;
    try {
      await this.video.play();
      if (generation === this.generation && this.mediaActive())
        this.statusTarget.textContent = "";
    } catch (error) {
      if (generation !== this.generation || !this.mediaActive()) return;
      if (error.name === "NotAllowedError" && !this.video.muted) {
        this.video.muted = true;
        try {
          await this.video.play();
          if (generation !== this.generation || !this.mediaActive()) return;
          this.statusTarget.textContent = "";
          this.playTarget.textContent = "turn sound on";
          this.playTarget.hidden = false;
          return;
        } catch {
          /* A click will retry at the current live position. */
        }
      }
      if (generation !== this.generation || !this.mediaActive()) return;
      this.playBlocked = true;
      this.playTarget.textContent = "play finale";
      this.playTarget.hidden = false;
      this.statusTarget.textContent =
        "press play to join the finale, or return to stardance";
    } finally {
      if (generation === this.generation) this.playing = false;
    }
  }

  playVideo() {
    if (!this.mediaActive()) return;
    this.playBlocked = false;
    this.playTarget.hidden = true;
    this.video.muted = false;
    if (this.mediaFailed) {
      this.mediaFailed = false;
      this.video.load();
    }
    this.syncVideo(true);
    this.attemptPlayback();
  }

  videoWaiting() {
    if (this.mediaActive()) this.statusTarget.textContent = "buffering…";
  }

  videoError() {
    this.mediaFailed = true;
    if (!this.mediaActive()) return;
    this.playBlocked = true;
    this.playTarget.textContent = "try again";
    this.playTarget.hidden = false;
    this.statusTarget.textContent =
      "the video couldn’t load — try again or press escape to return";
  }

  videoEnded() {
    if (!this.mediaActive()) return;
    this.mediaEnded = true;
    if (this.mode === "live") {
      this.tick();
    } else if (this.phase === "video") this.finish();
  }

  finish() {
    if (this.mode === "live") this.skipLive = true;
    this.cleanup();
  }

  preventClose(event) {
    event.preventDefault();
    this.finish();
  }

  releaseVideo() {
    this.video.pause();
    this.video.src = null;
    this.video.load();
  }

  cleanup({ restore = true } = {}) {
    if (this.hasCountdownTarget) this.countdownTarget.hidden = true;
    this.generation++;
    this.playing = false;
    this.fadeAnimation?.cancel();
    this.fadeAnimation = null;
    this.releaseVideo();
    this.dialogTarget.close();
    this.panelTarget.hidden = true;
    this.panelTarget.classList.remove("stardance-finale__panel--intro");
    this.originalClocks?.forEach((deadline, clock) =>
      clock.setAttribute(
        "data-stardance-countdown-override-at-value",
        deadline,
      ),
    );
    this.originalClocks?.clear();
    if (restore && this.phase !== "idle") this.dispatch("reset");
    this.phase = "idle";
    this.mode = null;
    if (restore && this.previousFocus?.isConnected)
      this.previousFocus.focus({ preventScroll: true });
  }
}
