// Presents a YouTube embed through the subset of HTMLMediaElement that the
// finale controller drives (src/load/play/pause/currentTime/muted/...), and
// re-dispatches player changes as the matching media events on the host
// element so existing data-action bindings keep working.

// YT.PlayerState values.
const ENDED = 0;
const PLAYING = 1;
const PAUSED = 2;
const BUFFERING = 3;
const CUED = 5;

// Browsers that block unmuted autoplay leave the player unstarted instead of
// rejecting, so a play request that never reaches PLAYING counts as blocked.
const BLOCKED_AFTER_MS = 1500;
const POLL_MS = 100;

const PLAYER_VARS = {
  controls: 0,
  disablekb: 1,
  fs: 0,
  iv_load_policy: 3,
  playsinline: 1,
  rel: 0,
};

let apiPromise = null;
function loadYoutubeApi() {
  if (window.YT?.Player) return Promise.resolve();
  if (apiPromise) return apiPromise;
  apiPromise = new Promise((resolve, reject) => {
    const previousReady = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      previousReady?.();
      resolve();
    };
    const script = document.createElement("script");
    script.src = "https://www.youtube.com/iframe_api";
    script.async = true;
    script.onerror = () => {
      apiPromise = null;
      reject(new Error("YouTube player unavailable"));
    };
    document.head.appendChild(script);
  });
  return apiPromise;
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export class YoutubeVideo {
  src = null;
  paused = true;
  readyState = 0;

  #element;
  #player = null;
  #ready = null;
  #session = 0;
  #muted = false;
  #pendingTime = 0;

  constructor(element) {
    this.#element = element;
  }

  get duration() {
    const duration = this.#player?.getDuration?.();
    return duration > 0 ? duration : NaN;
  }

  get currentTime() {
    if (this.#pendingTime !== null || !this.#started())
      return this.#pendingTime ?? 0;
    return this.#player.getCurrentTime();
  }

  set currentTime(seconds) {
    // Seeking a cued video starts playback, so hold the position until play().
    if (!this.#started()) {
      this.#pendingTime = seconds;
      return;
    }
    this.#pendingTime = null;
    this.#player.seekTo(seconds, true);
  }

  get seeking() {
    return this.#state() === BUFFERING;
  }

  get muted() {
    return this.#muted;
  }

  set muted(value) {
    this.#muted = value;
    if (!this.#player?.mute) return;
    if (value) this.#player.mute();
    else this.#player.unMute();
  }

  // Like HTMLMediaElement#load: (re)builds the player for `src`, or releases
  // the iframe and its buffers when `src` is cleared.
  load() {
    const session = ++this.#session;
    this.#destroy();
    if (!this.src) return;
    const videoId = this.src;
    this.#ready = loadYoutubeApi().then(
      () =>
        new Promise((resolve, reject) => {
          if (session !== this.#session) return reject(this.#aborted());
          const mount = document.createElement("div");
          this.#element.replaceChildren(mount);
          this.#player = new window.YT.Player(mount, {
            host: "https://www.youtube-nocookie.com",
            videoId,
            width: "100%",
            height: "100%",
            playerVars: { ...PLAYER_VARS, origin: window.location.origin },
            events: {
              onReady: () => {
                if (session !== this.#session) return;
                this.muted = this.#muted;
                this.readyState = 1;
                this.#emit("loadedmetadata");
                resolve();
              },
              onStateChange: ({ data }) => {
                if (session === this.#session) this.#stateChanged(data);
              },
              onError: () => {
                if (session !== this.#session) return;
                this.#emit("error");
                reject(new Error("YouTube playback error"));
              },
            },
          });
        }),
    );
    this.#ready.catch(() => {
      if (session === this.#session && !this.#player) this.#emit("error");
    });
  }

  async play() {
    const session = this.#session;
    if (!this.#ready) throw this.#aborted();
    await this.#ready;
    if (session !== this.#session) throw this.#aborted();
    if (this.#pendingTime !== null)
      this.#player.seekTo(this.#pendingTime, true);
    this.#player.playVideo();
    let blockedAt = performance.now() + BLOCKED_AFTER_MS;
    for (;;) {
      if (session !== this.#session) throw this.#aborted();
      const state = this.#state();
      if (state === PLAYING) {
        this.#pendingTime = null;
        return;
      }
      if (state === BUFFERING) blockedAt = performance.now() + BLOCKED_AFTER_MS;
      else if (performance.now() >= blockedAt) {
        this.#player.pauseVideo();
        throw new DOMException("Playback was blocked", "NotAllowedError");
      }
      await wait(POLL_MS);
    }
  }

  pause() {
    this.paused = true;
    this.#player?.pauseVideo?.();
  }

  #stateChanged(state) {
    if (state === PLAYING) {
      this.paused = false;
      this.readyState = 4;
      this.#emit("canplay");
    } else if (state === BUFFERING) {
      this.#emit("waiting");
    } else if (state === PAUSED) {
      this.paused = true;
    } else if (state === ENDED) {
      this.paused = true;
      this.#emit("ended");
    }
  }

  #started() {
    const state = this.#state();
    return state !== undefined && state !== -1 && state !== CUED;
  }

  #state() {
    return this.#player?.getPlayerState?.();
  }

  #destroy() {
    this.#player?.destroy();
    this.#player = null;
    this.#ready = null;
    this.#element.replaceChildren();
    this.paused = true;
    this.readyState = 0;
    this.#pendingTime = 0;
  }

  #emit(type) {
    this.#element.dispatchEvent(new Event(type));
  }

  #aborted() {
    return new DOMException("The player was released", "AbortError");
  }
}
