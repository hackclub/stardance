import { Controller } from "@hotwired/stimulus";

const FLUSH_INTERVAL_MS = 15000;
const READ_VISIBLE_MS = 4000;
const SCROLL_BUCKETS = [25, 50, 75, 100];
const VISIBILITY_PING_MIN_DELTA_MS = 1000;
const ACTIVITY_EVENTS = ["scroll", "keydown", "mousemove", "pointerdown"];

export default class extends Controller {
  static values = {
    assignmentId: Number,
    endpoint: { type: String, default: "/votes/events" },
  };

  connect() {
    this.queue = [];
    this.visibleMs = 0;
    this.focusedMs = 0;
    this.hiddenCount = 0;
    this.blurCount = 0;
    this.maxIdleGapMs = 0;
    this.lastTickAt = performance.now();
    this.lastActiveAt = performance.now();
    this.startedAt = performance.now();
    this.lastPingedVisibleMs = 0;
    this.sentScrollBuckets = new Set();
    this.readItems = new Set();
    this.pasteCount = 0;
    this.pastedCharCount = 0;
    this.feedbackTypingStart = null;
    this.feedbackDirty = false;
    this.feedbackWordCount = 0;
    this.feedbackCharCount = 0;

    this.bind();
    this.listen();
    this.setupTimelineObserver();

    this.tick = window.setInterval(() => this.recordTick(), 1000);
    this.flushTimer = window.setInterval(this.flush, FLUSH_INTERVAL_MS);
  }

  disconnect() {
    this.recordTick();
    this.queueVisibilityPing(true);
    this.queueFeedbackChange();
    this.flush();

    document.removeEventListener("visibilitychange", this.onVisibilityChange);
    window.removeEventListener("blur", this.onBlur);
    window.removeEventListener("focus", this.onFocus);
    window.removeEventListener("scroll", this.onScroll);
    window.removeEventListener("pagehide", this.flush);
    ACTIVITY_EVENTS.forEach((name) =>
      window.removeEventListener(name, this.onActivity),
    );
    this.scoreInputs?.forEach((input) =>
      input.removeEventListener("change", this.onScoreChange),
    );
    if (this.textarea) {
      this.textarea.removeEventListener("paste", this.onPaste);
      this.textarea.removeEventListener("input", this.onFeedbackInput);
    }
    this.observer?.disconnect();
    window.clearInterval(this.tick);
    window.clearInterval(this.flushTimer);
  }

  bind() {
    this.onVisibilityChange = this.onVisibilityChange.bind(this);
    this.onBlur = this.onBlur.bind(this);
    this.onFocus = this.onFocus.bind(this);
    this.onScroll = this.onScroll.bind(this);
    this.onActivity = this.onActivity.bind(this);
    this.onScoreChange = this.onScoreChange.bind(this);
    this.onPaste = this.onPaste.bind(this);
    this.onFeedbackInput = this.onFeedbackInput.bind(this);
    this.flush = this.flush.bind(this);
  }

  listen() {
    document.addEventListener("visibilitychange", this.onVisibilityChange);
    window.addEventListener("blur", this.onBlur);
    window.addEventListener("focus", this.onFocus);
    window.addEventListener("scroll", this.onScroll, { passive: true });
    window.addEventListener("pagehide", this.flush);
    ACTIVITY_EVENTS.forEach((name) =>
      window.addEventListener(name, this.onActivity, { passive: true }),
    );

    this.scoreInputs = Array.from(
      this.element.querySelectorAll(".vote-score__input"),
    );
    this.scoreInputs.forEach((input) =>
      input.addEventListener("change", this.onScoreChange),
    );

    this.textarea = this.element.querySelector(".vote-scorecard__textarea");
    if (this.textarea) {
      this.textarea.addEventListener("paste", this.onPaste);
      this.textarea.addEventListener("input", this.onFeedbackInput);
    }
  }

  setupTimelineObserver() {
    const cards = Array.from(
      this.element.querySelectorAll(".vote-page__timeline .feed-post-card"),
    );
    if (cards.length === 0) return;

    this.cardVisibleSince = new Map();
    this.observer = new IntersectionObserver(
      (entries) => this.onTimelineIntersection(entries),
      { threshold: [0, 0.7] },
    );
    cards.forEach((card, index) => {
      card.dataset.voteTelemetryIndex = index;
      this.observer.observe(card);
    });
  }

  onTimelineIntersection(entries) {
    const now = performance.now();
    entries.forEach((entry) => {
      const card = entry.target;
      const index = Number(card.dataset.voteTelemetryIndex);
      if (entry.intersectionRatio >= 0.7) {
        this.cardVisibleSince.set(index, now);
      } else {
        const since = this.cardVisibleSince.get(index);
        if (since != null) {
          this.maybeMarkRead(card, index, now - since);
          this.cardVisibleSince.delete(index);
        }
      }
    });
  }

  maybeMarkRead(card, index, visibleMs) {
    if (visibleMs < READ_VISIBLE_MS || this.readItems.has(index)) return;
    this.readItems.add(index);
    this.enqueue("vote_timeline_item_read", {
      item_index: index,
      item_kind: card.classList.contains("project-show__latest-ship")
        ? "ship"
        : "post",
      visible_ms: Math.round(visibleMs),
    });
  }

  recordTick() {
    const now = performance.now();
    const delta = now - this.lastTickAt;
    this.lastTickAt = now;

    if (document.visibilityState === "visible") {
      this.visibleMs += delta;
      if (document.hasFocus()) this.focusedMs += delta;
    }

    const idle = now - this.lastActiveAt;
    if (idle > this.maxIdleGapMs) this.maxIdleGapMs = idle;
  }

  onActivity() {
    this.lastActiveAt = performance.now();
  }

  onVisibilityChange() {
    if (document.visibilityState === "hidden") {
      this.hiddenCount += 1;
      this.recordTick();
      this.queueVisibilityPing();
      this.flush();
    } else {
      this.lastTickAt = performance.now();
      this.lastActiveAt = performance.now();
    }
  }

  onBlur() {
    this.blurCount += 1;
  }

  onFocus() {
    this.lastActiveAt = performance.now();
  }

  onScroll() {
    const doc = document.documentElement;
    const scrollable = doc.scrollHeight - window.innerHeight;
    if (scrollable <= 0) return;

    const pct = Math.min(100, Math.round((window.scrollY / scrollable) * 100));
    SCROLL_BUCKETS.forEach((bucket) => {
      if (pct >= bucket && !this.sentScrollBuckets.has(bucket)) {
        this.sentScrollBuckets.add(bucket);
        this.enqueue("vote_scroll_depth", { scroll_depth_pct: bucket });
      }
    });
  }

  onScoreChange(event) {
    this.enqueue("vote_score_changed", {
      category: event.target.name,
      score: Number(event.target.value),
      elapsed_ms: Math.round(performance.now() - this.startedAt),
    });
  }

  onPaste(event) {
    this.pasteCount += 1;
    const text = event.clipboardData?.getData("text") || "";
    this.pastedCharCount += text.length;
    this.enqueue("vote_feedback_pasted", {
      paste_count: this.pasteCount,
      pasted_char_count: this.pastedCharCount,
    });
  }

  onFeedbackInput() {
    if (this.feedbackTypingStart == null) {
      this.feedbackTypingStart = performance.now();
    }
    const value = this.textarea.value || "";
    this.feedbackCharCount = value.length;
    this.feedbackWordCount = value.trim().split(/\s+/).filter(Boolean).length;
    this.feedbackDirty = true;
  }

  queueFeedbackChange() {
    if (!this.feedbackDirty) return;
    this.feedbackDirty = false;
    this.enqueue("vote_feedback_changed", {
      word_count: this.feedbackWordCount,
      char_count: this.feedbackCharCount,
      typing_ms: this.feedbackTypingStart
        ? Math.round(performance.now() - this.feedbackTypingStart)
        : 0,
    });
  }

  queueVisibilityPing(force = false) {
    const delta = this.visibleMs - this.lastPingedVisibleMs;
    if (!force && delta < VISIBILITY_PING_MIN_DELTA_MS) return;
    this.lastPingedVisibleMs = this.visibleMs;
    this.enqueue("vote_visibility_ping", {
      visible_ms: Math.round(this.visibleMs),
      focused_ms: Math.round(this.focusedMs),
      hidden_count: this.hiddenCount,
      blur_count: this.blurCount,
      max_idle_gap_ms: Math.round(this.maxIdleGapMs),
      elapsed_ms: Math.round(performance.now() - this.startedAt),
    });
  }

  enqueue(eventType, properties) {
    if (!this.hasAssignmentIdValue) return;
    this.queue.push({
      event_type: eventType,
      vote_assignment_id: this.assignmentIdValue,
      properties,
    });
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content;
  }

  get endpointWithToken() {
    const token = this.csrfToken;
    if (!token) return this.endpointValue;
    return `${this.endpointValue}?authenticity_token=${encodeURIComponent(token)}`;
  }

  flush() {
    this.recordTick();
    this.queueFeedbackChange();
    this.queueVisibilityPing();

    if (this.queue.length === 0) return;

    const body = JSON.stringify({ events: this.queue });
    this.queue = [];

    if (navigator.sendBeacon) {
      navigator.sendBeacon(
        this.endpointWithToken,
        new Blob([body], { type: "application/json" }),
      );
    } else {
      fetch(this.endpointValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken,
        },
        body,
        keepalive: true,
      });
    }
  }
}
