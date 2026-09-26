import { Controller } from "@hotwired/stimulus";

// Reusable timelapse viewer for the shared recording gallery (hardware funding
// review + YSWS review). Each gallery tile is a clickable <a> pointing at the
// raw video; clicking one opens a modal lightbox with a Video.js player and a
// Premiere-style JKL transport layered on top of it.
//
// Self-contained: the lightbox is appended to document.body (the gallery panel
// is small and clip-scrolled), and the keydown listener is bound ONLY while the
// lightbox is open so it never fights page typing when closed.
export default class extends Controller {
  static targets = ["item"];
  // The Video.js skin is its own bundle (app/javascript/lapse_player_skin.js),
  // so only review pages with a gallery download it, not every visitor.
  static values = { skinUrl: String };

  // One shared signed-speed ladder: L nudges toward faster-forward, J toward
  // faster-reverse, meeting in the middle (…4×▶ 2×▶ 1×▶ | 1×◀ 2×◀…). So from 8×
  // forward, J steps down to 4×.
  RATE_LADDER = [-8, -4, -2, -1, 1, 2, 4, 8];

  // Above this a clip streams from the network instead of being cached whole,
  // so one huge recording can't balloon the tab's memory.
  MAX_CACHE_BYTES = 512 * 1024 * 1024;

  // Start fetching the skin as soon as a gallery appears, so it's ready by the
  // time a reviewer clicks a tile.
  connect() {
    this.skinLoaded = import(this.skinUrlValue);
  }

  disconnect() {
    this.closeLightbox();
  }

  // Clicking a tile opens it in the lightbox instead of navigating to the raw
  // video. Builds the playlist from every sibling tile and opens at the clicked
  // index. Modified/non-primary clicks still follow the href (browser default).
  async open(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button > 0)
      return;
    event.preventDefault();
    const sources = this.itemTargets.map((tile) => tile.href);
    const index = Math.max(0, this.itemTargets.indexOf(event.currentTarget));
    await this.skinLoaded;
    this.showLightbox(sources, index);
  }

  // ── Keyboard (bound only while the lightbox is open) ─────────────────────
  // Runs in the capture phase so nothing else on the page (e.g. the YSWS review
  // shortcuts) — nor the skin's own hotkeys — sees the keys we claim; the rest
  // (f, 0–9, Home/End) fall through to the skin.
  onKeydown = (event) => {
    if (!this.lightbox || event.altKey) return;
    if (event.key === "Escape") return this.consume(event, this.closeLightbox);
    // Ctrl/⌘ + Shift + ←/→ pages between recordings (plain and shift-only
    // arrows stay bound to scrubbing).
    if (
      (event.ctrlKey || event.metaKey) &&
      event.shiftKey &&
      (event.key === "ArrowLeft" || event.key === "ArrowRight")
    )
      return this.consume(event, () =>
        this.stepLightbox(event.key === "ArrowLeft" ? -1 : 1),
      );
    if (event.ctrlKey || event.metaKey) return;

    if (event.code === "Space" || event.code === "KeyK")
      return this.consume(event, this.togglePlay);
    if (event.code === "KeyJ")
      return this.consume(event, () => this.nudgeRate(-1));
    if (event.code === "KeyL")
      return this.consume(event, () => this.nudgeRate(1));
    // vim: h mirrors ← scrub (→'s vim key `l` is taken by forward-transport).
    if (event.key === "ArrowLeft" || event.code === "KeyH")
      return this.consume(event, () =>
        this.stepVideo(event.shiftKey ? -10 : -1),
      );
    if (event.key === "ArrowRight")
      return this.consume(event, () => this.stepVideo(event.shiftKey ? 10 : 1));
  };

  consume(event, fn) {
    event.preventDefault();
    event.stopImmediatePropagation();
    fn();
  }

  // ── Lightbox ─────────────────────────────────────────────────────────────
  showLightbox(sources, index) {
    this.closeLightbox();
    this.sources = sources;
    this.index = index;
    this.cache = new Map(); // src → Promise<objectURL | null>
    this.fetches = new AbortController();

    const box = document.createElement("div");
    box.className = "lapse-player__lightbox";
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-modal", "true");

    const close = document.createElement("button");
    close.type = "button";
    close.className = "lapse-player__close";
    close.setAttribute("aria-label", "Close");
    close.textContent = "×";
    close.addEventListener("click", this.closeLightbox);

    this.stage = document.createElement("div");
    this.stage.className = "lapse-player__stage";
    this.caption = document.createElement("p");
    this.caption.className = "lapse-player__caption";

    box.append(close, this.stage, this.caption);
    document.body.appendChild(box);
    this.lightbox = box;
    window.addEventListener("keydown", this.onKeydown, true);

    this.mountVideo();
  }

  mountVideo() {
    this.stopReverse();
    const src = this.sources[this.index];

    const player = document.createElement("video-player");
    const skin = document.createElement("lapse-player-skin");
    skin.className = "lapse-player__skin";
    const video = document.createElement("video");
    Object.assign(video, {
      src,
      // autoplay, not play(): the Video.js player reloads the source once it
      // attaches, which would cancel an early play() call.
      autoplay: true,
      playsInline: true,
      preload: "auto",
      // Timelapses are silent screen captures; muted also keeps autoplay from
      // being blocked.
      muted: true,
    });
    video.addEventListener("ended", () => this.applyRate(0));
    // Only the first load autoplays; swapping to the cached copy later must not
    // resume a clip the reviewer has paused.
    video.addEventListener("playing", () => (video.autoplay = false), {
      once: true,
    });
    // Keep the ladder in sync when the player's own controls change playback.
    // Like K, the play button resumes at +1×, never at a stale J/L speed.
    video.addEventListener("play", () => {
      if (this.rate <= 0) this.applyRate(1);
    });
    video.addEventListener("pause", () => {
      if (!this.reverseTimer && !video.ended) this.setRate(0);
    });
    video.addEventListener("ratechange", () => {
      if (!video.paused) this.setRate(video.playbackRate);
    });

    skin.append(video, this.buildSpeedLadder());
    player.appendChild(skin);
    this.stage.replaceChildren(player);
    this.video = video;
    this.lastRate = 1; // K resumes here after a pause
    this.setRate(0); // the play event lights 1▶ once autoplay actually starts

    this.cacheVideo(src).then((url) => this.swapToCached(video, src, url));
  }

  // ── Aggressive buffering ─────────────────────────────────────────────────
  // Playback starts straight off the network while the whole clip downloads
  // into memory; once it lands, the player swaps to the local copy so seeks,
  // 8× and reverse never wait on the network. The next recording is then
  // prefetched so paging forward is instant too. If the media host refuses the
  // cross-origin fetch, the player just keeps streaming.
  cacheVideo(src) {
    if (!this.cache.has(src)) this.cache.set(src, this.download(src));
    return this.cache.get(src);
  }

  async download(src) {
    try {
      const response = await fetch(src, { signal: this.fetches.signal });
      const total = Number(response.headers.get("content-length"));
      if (!response.ok || total > this.MAX_CACHE_BYTES) return null;

      const reader = response.body.getReader();
      const chunks = [];
      let loaded = 0;
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(value);
        loaded += value.length;
        if (total && src === this.sources?.[this.index])
          this.cacheProgress = Math.floor((loaded / total) * 100);
        this.syncCaption();
      }
      return URL.createObjectURL(
        new Blob(chunks, { type: response.headers.get("content-type") }),
      );
    } catch {
      return null;
    }
  }

  swapToCached(video, src, url) {
    if (video !== this.video) return;
    this.cacheProgress = url ? 100 : null;
    this.syncCaption();
    if (!url) return;

    const { currentTime } = video;
    const rate = this.rate;
    video.addEventListener(
      "loadedmetadata",
      () => {
        video.currentTime = currentTime;
        this.applyRate(rate);
      },
      { once: true },
    );
    video.src = url;
    const next = this.sources[(this.index + 1) % this.sources.length];
    if (next !== src) this.cacheVideo(next);
  }

  // ── Speed ladder ─────────────────────────────────────────────────────────
  buildSpeedLadder() {
    const ladder = document.createElement("div");
    ladder.className = "lapse-player__speed";
    ladder.slot = "speed"; // lands in the skin's control bar
    const label = document.createElement("span");
    label.className = "lapse-player__speed-label";
    label.textContent = "JKL";
    ladder.appendChild(label);
    this.pills = this.RATE_LADDER.map((rate) => {
      const pill = document.createElement("button");
      pill.type = "button";
      pill.className = "lapse-player__pill";
      pill.textContent = rate < 0 ? `${-rate}◀` : `${rate}▶`;
      pill.title = `${rate < 0 ? "reverse" : "forward"} ${Math.abs(rate)}× · j / l`;
      pill.addEventListener("click", () => this.applyRate(rate));
      ladder.appendChild(pill);
      return pill;
    });
    return ladder;
  }

  // Records the signed speed and repaints the ladder + caption, without
  // touching the video.
  setRate(rate) {
    this.rate = rate;
    if (rate) this.lastRate = rate;
    this.pills?.forEach((pill, i) =>
      pill.classList.toggle(
        "lapse-player__pill--active",
        this.RATE_LADDER[i] === rate,
      ),
    );
    this.syncCaption();
  }

  syncCaption() {
    if (!this.caption) return;
    const parts = [`${this.index + 1} / ${this.sources.length}`];
    if (this.cacheProgress != null && this.cacheProgress < 100)
      parts.push(`caching ${this.cacheProgress}%`);
    parts.push("j/k/l transport", "←/→ scrub (shift = 10s)");
    if (this.sources.length > 1) parts.push("⌃⇧←/→ next lapse");
    parts.push("esc to close");
    this.caption.textContent = parts.join(" · ");
  }

  // ── Premiere-style JKL transport ─────────────────────────────────────────
  nudgeRate(direction) {
    if (!this.rate) return this.applyRate(direction > 0 ? 1 : -1);
    const i = this.RATE_LADDER.indexOf(this.rate);
    if (i === -1) return this.applyRate(direction > 0 ? 1 : -1);
    const next = Math.max(
      0,
      Math.min(this.RATE_LADDER.length - 1, i + direction),
    );
    this.applyRate(this.RATE_LADDER[next]);
  }

  // K: pause when playing, resume when paused. Pausing also resets the resume
  // speed to +1× so play always restarts forward (never at a stale J/L speed).
  togglePlay = () => {
    if (this.rate) {
      this.applyRate(0);
      this.lastRate = 1;
    } else {
      this.applyRate(this.lastRate || 1);
    }
  };

  applyRate(rate) {
    if (!this.video) return;
    this.stopReverse();
    this.setRate(rate);
    if (rate > 0) {
      this.video.playbackRate = rate;
      this.video.play().catch(() => {});
    } else if (rate < 0) {
      this.startReverse(-rate);
    } else {
      this.video.pause();
    }
  }

  // HTML5 video can't play backwards, so reverse walks currentTime back on a
  // timer; with the clip cached locally every one of those seeks is instant.
  startReverse(speed) {
    this.reverseTimer = setInterval(() => {
      const t = this.video.currentTime - speed * 0.066;
      if (t <= 0) {
        this.video.currentTime = 0;
        this.applyRate(0);
      } else {
        this.video.currentTime = t;
      }
    }, 66);
    this.video.pause();
  }

  stopReverse() {
    clearInterval(this.reverseTimer);
    this.reverseTimer = null;
  }

  stepVideo(seconds) {
    if (!this.video) return;
    this.applyRate(0); // frame-scrub pauses first
    const max = this.video.duration || Number.MAX_SAFE_INTEGER;
    this.video.currentTime = Math.max(
      0,
      Math.min(max, this.video.currentTime + seconds),
    );
  }

  stepLightbox(direction) {
    const count = this.sources.length;
    this.index = (this.index + direction + count) % count;
    this.cacheProgress = null;
    this.mountVideo();
  }

  closeLightbox = () => {
    this.stopReverse();
    window.removeEventListener("keydown", this.onKeydown, true);
    this.fetches?.abort();
    this.cache?.forEach((pending) =>
      pending.then((url) => url && URL.revokeObjectURL(url)),
    );
    this.lightbox?.remove();
    this.lightbox = this.video = this.cache = this.fetches = null;
  };
}
