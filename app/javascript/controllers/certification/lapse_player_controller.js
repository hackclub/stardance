import { Controller } from "@hotwired/stimulus";

// Reusable timelapse viewer for the shared recording gallery (hardware funding
// review + YSWS review). Each gallery tile is a clickable <a> pointing at the
// raw video; clicking one opens a modal lightbox with a Premiere-style JKL
// transport instead of navigating away.
//
// Self-contained: the lightbox is appended to document.body (the gallery panel
// is small and clip-scrolled), and the document keydown listener is bound ONLY
// while the lightbox is open so it never fights page typing when closed.
export default class extends Controller {
  static targets = ["item"];

  disconnect() {
    this.stopReverse();
    this.closeLightbox();
  }

  // Clicking a tile opens it in the JKL lightbox instead of navigating to the
  // raw R2 video. Builds the playlist from every sibling tile and opens at the
  // clicked index. ctrl/middle-click still follows the href (browser default).
  open(event) {
    event.preventDefault();
    const link = event.currentTarget;
    const items = this.itemTargets.map((tile) => ({ type: "video", src: tile.href }));
    if (!items.length) return;
    this.showLightbox(items, Math.max(0, this.itemTargets.indexOf(link)));
  }

  // ── Modal keyboard shortcuts (bound only while the lightbox is open) ──────
  onKeydown(event) {
    if (!this.lightbox || event.altKey) return;
    if (event.key === "Escape") return this.consume(event, () => this.closeLightbox());
    // Video → Premiere-style JKL transport + arrow scrubbing (shift = coarse).
    if (this.lbVideo) {
      if (event.code === "Space") return this.consume(event, () => this.togglePlay());
      if (event.code === "KeyJ") return this.consume(event, () => this.nudgeRate(-1));
      if (event.code === "KeyK") return this.consume(event, () => this.togglePlay());
      if (event.code === "KeyL") return this.consume(event, () => this.nudgeRate(1));
      // vim: h mirrors ← scrub (→'s vim key `l` is taken by forward-transport).
      if (event.key === "ArrowLeft" || event.code === "KeyH") return this.consume(event, () => this.stepVideo(event.shiftKey ? -10 : -1));
      if (event.key === "ArrowRight") return this.consume(event, () => this.stepVideo(event.shiftKey ? 10 : 1));
      return;
    }
    // Non-video slides → prev/next (vim h/l mirror ←/→).
    if (event.key === "ArrowLeft" || event.code === "KeyH") return this.consume(event, () => this.stepLightbox(-1));
    if (event.key === "ArrowRight" || event.code === "KeyL") return this.consume(event, () => this.stepLightbox(1));
  }

  consume(event, fn) {
    event.preventDefault();
    fn();
  }

  // ── Lightbox ─────────────────────────────────────────────────────────────
  showLightbox(items, index) {
    this.closeLightbox();
    this.lbItems = items;
    this.lbIndex = index;

    const box = document.createElement("div");
    box.className = "lapse-player__lightbox";
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-modal", "true");
    // Backdrop click closes a non-video lightbox; for video it doesn't — so
    // clicking near the player (to pause) never closes it. Use × or esc.
    box.addEventListener("click", (e) => { if (e.target === box && !this.lbVideo) this.closeLightbox(); });

    const close = document.createElement("button");
    close.type = "button";
    close.className = "lapse-player__lightbox-close";
    close.setAttribute("aria-label", "Close");
    close.textContent = "×";
    close.addEventListener("click", () => this.closeLightbox());

    this.lbStage = document.createElement("div");
    this.lbStage.className = "lapse-player__lightbox-stage";
    this.lbCaption = document.createElement("p");
    this.lbCaption.className = "lapse-player__lightbox-caption";

    box.append(close, this.lbStage, this.lbCaption);
    document.body.appendChild(box);
    this.lightbox = box;

    this.onKeydown = this.onKeydown.bind(this);
    document.addEventListener("keydown", this.onKeydown);

    this.renderLightbox();
  }

  renderLightbox() {
    const item = this.lbItems[this.lbIndex];
    this.stopReverse();
    this.lbStage.innerHTML = "";
    if (item.type === "video") {
      this.mountVideoPlayer(item);
    } else {
      const img = document.createElement("img");
      img.src = item.src;
      img.alt = item.alt || "";
      img.className = "lapse-player__lightbox-media";
      this.lbStage.appendChild(img);
      this.lbVideo = null;
      const nav = this.lbItems.length > 1 ? " · ←/→" : "";
      this.lbCaption.textContent = `${this.lbIndex + 1} / ${this.lbItems.length}${nav} · esc to close`;
    }
  }

  // ── Custom player chrome ─────────────────────────────────────────────────
  // Native controls are off so the transport has one look: a scrubber, a
  // play/pause + frame-step cluster, and a visual JKL speed ladder. Every
  // control calls the same methods the keyboard does, so the two stay in sync.
  mountVideoPlayer(item) {
    const video = document.createElement("video");
    Object.assign(video, { src: item.src, controls: false, autoplay: true, playsInline: true });
    video.className = "lapse-player__lightbox-media";
    video.addEventListener("click", (event) => { event.stopPropagation(); this.togglePlay(); });
    video.addEventListener("loadedmetadata", () => this.syncPlayerUI());
    video.addEventListener("timeupdate", () => this.syncPlayerUI());
    video.addEventListener("ended", () => this.applyRate(0));
    this.lbVideo = video;
    this.rate = 1;      // signed speed: + forward, − reverse, 0 paused (autoplay = 1×)
    this.lastRate = 1;  // K resumes here after a pause

    this.lbStage.append(video, this.buildPlayerBar());
    this.syncPlayerUI();
  }

  // Vimeo/Plyr-style layout: a full-width scrubber (buffered + played + a handle
  // that appears on hover) above a control row split into a left transport
  // cluster and a right JKL speed ladder.
  buildPlayerBar() {
    const bar = document.createElement("div");
    bar.className = "lapse-player__player";

    const scrub = document.createElement("div");
    scrub.className = "lapse-player__player-scrub";
    this.lbBuffered = document.createElement("div");
    this.lbBuffered.className = "lapse-player__player-buffered";
    this.lbProgress = document.createElement("div");
    this.lbProgress.className = "lapse-player__player-progress";
    this.lbHandle = document.createElement("div");
    this.lbHandle.className = "lapse-player__player-handle";
    this.lbProgress.appendChild(this.lbHandle);
    scrub.append(this.lbBuffered, this.lbProgress);
    scrub.addEventListener("pointerdown", (event) => this.scrubFrom(event, scrub));

    const row = document.createElement("div");
    row.className = "lapse-player__player-row";

    const left = document.createElement("div");
    left.className = "lapse-player__player-cluster";
    this.lbPlayBtn = this.playerButton("❚❚", "Play / pause · k or space", () => this.togglePlay());
    const back = this.playerButton("⟨", "Step back 1s · ← / h (shift = 10s)", () => this.stepVideo(-1));
    const fwd = this.playerButton("⟩", "Step forward 1s · → (shift = 10s)", () => this.stepVideo(1));
    this.lbTime = document.createElement("span");
    this.lbTime.className = "lapse-player__player-time";
    left.append(this.lbPlayBtn, back, fwd, this.lbTime);

    const right = document.createElement("div");
    right.className = "lapse-player__player-cluster";
    const speed = document.createElement("div");
    speed.className = "lapse-player__player-speed";
    const speedLabel = document.createElement("span");
    speedLabel.className = "lapse-player__player-speed-label";
    speedLabel.textContent = "JKL";
    speed.appendChild(speedLabel);
    this.lbSpeedPills = this.RATE_LADDER.map((r) => {
      const pill = document.createElement("button");
      pill.type = "button";
      pill.className = "lapse-player__player-pill";
      pill.textContent = r < 0 ? `${-r}◀` : `${r}▶`;
      pill.title = `${r < 0 ? "reverse" : "forward"} ${Math.abs(r)}× · j / l`;
      pill.addEventListener("click", () => this.applyRate(r));
      speed.appendChild(pill);
      return pill;
    });
    right.appendChild(speed);

    row.append(left, right);
    bar.append(scrub, row);
    return bar;
  }

  playerButton(label, title, onClick) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "lapse-player__player-btn";
    button.title = title;
    button.textContent = label;
    button.addEventListener("click", onClick);
    return button;
  }

  // Click / drag anywhere on the track to seek (pauses first, like a scrub).
  scrubFrom(event, track) {
    const seek = (clientX) => {
      if (!this.lbVideo?.duration) return;
      const rect = track.getBoundingClientRect();
      const frac = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
      this.applyRate(0);
      this.lbVideo.currentTime = frac * this.lbVideo.duration;
      this.syncPlayerUI();
    };
    seek(event.clientX);
    const move = (e) => seek(e.clientX);
    const up = () => {
      document.removeEventListener("pointermove", move);
      document.removeEventListener("pointerup", up);
    };
    document.addEventListener("pointermove", move);
    document.addEventListener("pointerup", up);
  }

  syncPlayerUI() {
    if (!this.lbVideo) return;
    const video = this.lbVideo;
    if (this.lbPlayBtn) this.lbPlayBtn.textContent = this.rate ? "❚❚" : "▶";
    const pct = video.duration ? (video.currentTime / video.duration) * 100 : 0;
    if (this.lbProgress) this.lbProgress.style.width = `${pct}%`;
    if (this.lbBuffered && video.duration && video.buffered.length) {
      const end = video.buffered.end(video.buffered.length - 1);
      this.lbBuffered.style.width = `${(end / video.duration) * 100}%`;
    }
    if (this.lbTime) this.lbTime.textContent = `${this.fmtTime(video.currentTime)} / ${this.fmtTime(video.duration)}`;
    this.lbSpeedPills?.forEach((pill, i) => pill.classList.toggle("is-active", this.RATE_LADDER[i] === this.rate));
    if (this.lbCaption) {
      this.lbCaption.textContent =
        `${this.lbIndex + 1} / ${this.lbItems.length} · j/k/l transport · ←/→ scrub (shift = 10s) · esc to close`;
    }
  }

  fmtTime(seconds) {
    if (!isFinite(seconds)) return "0:00";
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  // ── Premiere-style JKL transport ─────────────────────────────────────────
  // One shared signed-speed ladder: L nudges toward faster-forward, J toward
  // faster-reverse, meeting in the middle (…4×▶ 2×▶ 1×▶ | 1×◀ 2×◀…). So from 8×
  // forward, J steps down to 4×. HTML5 video can't play backwards, so reverse is
  // emulated with a timer that walks currentTime back.
  RATE_LADDER = [ -8, -4, -2, -1, 1, 2, 4, 8 ];

  nudgeRate(direction) {
    if (!this.lbVideo) return;
    let next;
    if (!this.rate) {
      next = direction > 0 ? 1 : -1;
    } else {
      const i = this.RATE_LADDER.indexOf(this.rate);
      next = i === -1
        ? (direction > 0 ? 1 : -1)
        : this.RATE_LADDER[Math.max(0, Math.min(this.RATE_LADDER.length - 1, i + direction))];
    }
    this.applyRate(next);
  }

  // K: pause when playing, resume when paused. Pausing also resets the resume
  // speed to +1× so play always restarts forward (never at a stale J/L speed).
  togglePlay() {
    if (!this.lbVideo) return;
    if (this.rate) {
      this.lastRate = 1;
      this.applyRate(0);
    } else {
      this.applyRate(this.lastRate || 1);
    }
  }

  applyRate(rate) {
    if (!this.lbVideo) return;
    this.rate = rate;
    if (rate) this.lastRate = rate;
    this.stopReverse();
    if (rate > 0) {
      this.lbVideo.playbackRate = rate;
      this.lbVideo.play();
    } else if (rate < 0) {
      this.lbVideo.pause();
      this.reverseSpeed = -rate;
      this.startReverse();
    } else {
      this.lbVideo.pause();
    }
    this.syncPlayerUI();
  }

  startReverse() {
    this.stopReverse();
    this.reverseTimer = setInterval(() => {
      if (!this.lbVideo) return this.stopReverse();
      const t = this.lbVideo.currentTime - this.reverseSpeed * 0.066;
      if (t <= 0) {
        this.lbVideo.currentTime = 0;
        this.applyRate(0); // hit the start → stop
      } else {
        this.lbVideo.currentTime = t;
      }
    }, 66);
  }

  stopReverse() {
    clearInterval(this.reverseTimer);
    this.reverseTimer = null;
  }

  stepVideo(seconds) {
    if (!this.lbVideo) return;
    this.applyRate(0); // frame-scrub pauses first
    const max = this.lbVideo.duration || Number.MAX_SAFE_INTEGER;
    this.lbVideo.currentTime = Math.max(0, Math.min(max, this.lbVideo.currentTime + seconds));
    this.syncPlayerUI();
  }

  stepLightbox(direction) {
    const count = this.lbItems.length;
    this.lbIndex = (this.lbIndex + direction + count) % count;
    this.renderLightbox();
  }

  closeLightbox() {
    this.stopReverse();
    if (this.onKeydown) document.removeEventListener("keydown", this.onKeydown);
    this.lightbox?.remove();
    this.lightbox = null;
    this.lbVideo = null;
  }
}
