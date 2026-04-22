import { Controller } from "@hotwired/stimulus";

// Shared scheduler — all word-cycle controllers tick off this single timer,
// so rows stay in phase regardless of word length or anchor pauses. Each
// row offsets its own delete/type sequence via its `delay` within the tick.
const scheduler = {
  listeners: new Set(),
  tickCount: 0,
  timer: null,
  config: null,

  register(fn, config) {
    if (this.listeners.size === 0) {
      this.config = config;
      this.start();
    }
    this.listeners.add(fn);
    return () => {
      this.listeners.delete(fn);
      if (this.listeners.size === 0) this.stop();
    };
  },

  start() {
    const tick = () => {
      this.tickCount += 1;
      const isAnchor = this.tickCount % this.config.anchorEvery === 0;
      for (const listener of this.listeners) listener(this.tickCount, isAnchor);
      const pause = isAnchor ? this.config.anchorPause : 0;
      this.timer = setTimeout(tick, this.config.interval + pause);
    };
    this.timer = setTimeout(tick, this.config.firstDelay ?? this.config.interval);
  },

  stop() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    this.tickCount = 0;
    this.config = null;
  },
};

const MOBILE_QUERY = "(max-width: 600px)";

export default class extends Controller {
  static values = {
    words: Array,
    mobileWords: Array,
    anchor: String,
    anchorEvery: { type: Number, default: 5 },
    anchorPause: { type: Number, default: 2200 },
    interval: { type: Number, default: 3400 },
    firstDelay: { type: Number, default: 1400 },
    typeSpeed: { type: Number, default: 65 },
    deleteSpeed: { type: Number, default: 28 },
    delay: { type: Number, default: 0 },
  };

  connect() {
    if (!this.hasWordsValue || this.wordsValue.length === 0) return;

    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)");
    if (reduce?.matches) return;

    this.currentText = this.element.textContent;
    this.lastWord = this.currentText.trim();
    this.element.style.display = "inline-block";
    this.element.classList.add("word-cycle");
    // If the baked-in initial text is already the anchor (the "punchline"
    // form), start in the held state so it reads as a complete phrase —
    // no cursor, warm tint — until the first tick kicks off the cycle.
    if (this.hasAnchorValue && this.lastWord === this.anchorValue) {
      this.element.classList.add("word-cycle--held");
    }

    this.mobileQuery = window.matchMedia?.(MOBILE_QUERY);

    this.unsubscribe = scheduler.register(
      (tickCount, isAnchor) => this.onTick(tickCount, isAnchor),
      {
        interval: this.intervalValue,
        anchorEvery: this.anchorEveryValue,
        anchorPause: this.anchorPauseValue,
        firstDelay: this.firstDelayValue,
      }
    );
  }

  disconnect() {
    if (this.unsubscribe) this.unsubscribe();
    if (this.tickTimer) clearTimeout(this.tickTimer);
    if (this.charTimer) clearTimeout(this.charTimer);
  }

  onTick(_tickCount, isAnchor) {
    if (this.tickTimer) clearTimeout(this.tickTimer);
    this.tickTimer = setTimeout(() => this.startDelete(isAnchor), this.delayValue);
  }

  startDelete(isAnchor) {
    if (this.charTimer) clearTimeout(this.charTimer);
    this.element.classList.remove("word-cycle--held");
    this.nextWord = this.pickNext(isAnchor);
    this.deleteChar();
  }

  deleteChar() {
    if (this.currentText.length === 0) {
      this.typeChar();
      return;
    }
    this.currentText = this.currentText.slice(0, -1);
    this.element.textContent = this.currentText;
    this.charTimer = setTimeout(() => this.deleteChar(), this.deleteSpeedValue);
  }

  typeChar() {
    if (this.currentText === this.nextWord) {
      this.lastWord = this.nextWord;
      if (this.hasAnchorValue && this.nextWord === this.anchorValue) {
        this.element.classList.add("word-cycle--held");
      }
      return;
    }
    this.currentText = this.nextWord.slice(0, this.currentText.length + 1);
    this.element.textContent = this.currentText;
    this.charTimer = setTimeout(() => this.typeChar(), this.typeSpeedValue);
  }

  // Pick from the mobile-safe list when the viewport is narrow enough that
  // long words would wrap the headline; otherwise use the full list.
  activePool() {
    const isMobile = this.mobileQuery?.matches;
    if (isMobile && this.hasMobileWordsValue && this.mobileWordsValue.length > 0) {
      return this.mobileWordsValue;
    }
    return this.wordsValue;
  }

  pickNext(isAnchor) {
    if (isAnchor && this.hasAnchorValue && this.anchorValue) {
      return this.anchorValue;
    }
    const source = this.activePool();
    const pool = source.filter((w) => w !== this.lastWord);
    if (pool.length === 0) return source[0];
    return pool[Math.floor(Math.random() * pool.length)];
  }
}
