import { Controller } from "@hotwired/stimulus";

const IMPRESSION_RATIO = 0.5;
const READ_RATIO = 0.7;
const IMPRESSION_MS = 1000;
const READ_CONTINUOUS_MS = 4000;
const READ_CUMULATIVE_MS = 8000;
const DWELL_BUCKETS = [8000, 15000, 30000, 60000];
const VIDEO_PROGRESS_BUCKETS = [25, 50, 75, 100];

export default class extends Controller {
  static values = {
    itemType: String,
    postId: Number,
    projectId: Number,
    postType: String,
    source: String,
    position: Number,
    page: Number,
    feedRequestId: String,
  };

  connect() {
    this.visibleSince = null;
    this.visibleMs = 0;
    this.lastTickAt = null;
    this.sent = new Set();
    this.seenDwellBuckets = new Set();
    this.seenVideoBuckets = new Set();
    this.feedRequestId ||= crypto.randomUUID();

    this.observer = new IntersectionObserver(this.onIntersection, {
      threshold: [0, 0.5, 0.7, 1],
    });
    this.observer.observe(this.element);

    this.tick = window.setInterval(() => this.recordVisibility(), 1000);
    this.element.addEventListener("click", this.onOpen);
    this.element.querySelectorAll("video").forEach((video) => {
      video.addEventListener("timeupdate", this.onVideoProgress);
    });
  }

  disconnect() {
    this.recordVisibility();
    this.observer?.disconnect();
    window.clearInterval(this.tick);
    this.element.removeEventListener("click", this.onOpen);
    this.element.querySelectorAll("video").forEach((video) => {
      video.removeEventListener("timeupdate", this.onVideoProgress);
    });
  }

  onIntersection = (entries) => {
    const entry = entries[0];
    this.visibilityRatio = entry.intersectionRatio;

    if (
      entry.intersectionRatio >= IMPRESSION_RATIO &&
      this.visibleSince === null
    ) {
      this.visibleSince = performance.now();
      this.lastTickAt = this.visibleSince;
    } else if (entry.intersectionRatio < IMPRESSION_RATIO) {
      this.recordVisibility();
      this.visibleSince = null;
      this.lastTickAt = null;
    }
  };

  onOpen = (event) => {
    if (event.target.closest("a, button, summary")) {
      this.sendOnce("open");
    }
  };

  onVideoProgress = (event) => {
    const video = event.currentTarget;
    if (!video.duration || Number.isNaN(video.duration)) return;

    const progress = Math.floor((video.currentTime / video.duration) * 100);
    VIDEO_PROGRESS_BUCKETS.forEach((bucket) => {
      if (progress >= bucket && !this.seenVideoBuckets.has(bucket)) {
        this.seenVideoBuckets.add(bucket);
        this.send("video_progress", { progress: bucket });
        if (bucket >= 25) this.sendOnce("read");
      }
    });
  };

  recordVisibility() {
    if (this.visibleSince === null || this.lastTickAt === null) return;

    const now = performance.now();
    const delta = now - this.lastTickAt;
    this.lastTickAt = now;
    this.visibleMs += delta;

    if (this.visibleMs >= IMPRESSION_MS) this.sendOnce("impression");
    if (
      this.visibilityRatio >= READ_RATIO &&
      now - this.visibleSince >= READ_CONTINUOUS_MS
    ) {
      this.sendOnce("read");
    }
    if (this.visibleMs >= READ_CUMULATIVE_MS) this.sendOnce("read");

    DWELL_BUCKETS.forEach((bucket) => {
      if (this.visibleMs >= bucket && !this.seenDwellBuckets.has(bucket)) {
        this.seenDwellBuckets.add(bucket);
        this.send("dwell", { bucket: bucket / 1000 });
      }
    });
  }

  sendOnce(eventType) {
    if (!this.sent.has(eventType)) {
      this.sent.add(eventType);
      this.send(eventType);
    }
  }

  send(eventType, extras = {}) {
    const payload = {
      events: [
        {
          event_type: eventType,
          item_type: this.itemTypeValue || "post",
          post_id: this.hasPostIdValue ? this.postIdValue : null,
          project_id: this.hasProjectIdValue ? this.projectIdValue : null,
          post_type: this.postTypeValue,
          source: this.sourceValue,
          position: this.hasPositionValue ? this.positionValue : null,
          page: this.hasPageValue ? this.pageValue : null,
          feed_request_id: this.feedRequestId,
          visible_ms: Math.round(this.visibleMs),
          visibility_ratio: this.visibilityRatio,
          ...extras,
        },
      ],
    };

    const body = JSON.stringify(payload);
    if (navigator.sendBeacon) {
      navigator.sendBeacon(
        "/feed_events",
        new Blob([body], { type: "application/json" }),
      );
    } else {
      fetch("/feed_events", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")
            ?.content,
        },
        body,
        keepalive: true,
      });
    }
  }
}
