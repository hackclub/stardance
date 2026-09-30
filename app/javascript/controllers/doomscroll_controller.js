import { Controller } from "@hotwired/stimulus";

// Doomscroll mode for the home feed, after Starscroll: the feed frame becomes a
// full-screen stack with one post per screen. Scrolling is paged — every wheel
// flick, swipe, or key press moves exactly one post with an eased glide, so the
// feed never rests between posts. It reuses the normal feed markup and
// lazy-frame pagination; only presentation, input, and video autoplay change.
const CARD_SELECTOR = "article.feed-post-card";
const VIDEO_SELECTOR = "video.feed-post-card__video";
const ACTIVE_CLASS = "feed-home--doomscroll";
const RETURNING_CLASS = "feed-home--doomscroll-returning";
const CURRENT_CLASS = "feed-post-card--doomscroll-current";
const BODY_OPEN_CLASS = "feed-home-doomscroll-open";
const IN_SIDEBAR_CLASS = "feed-home--doomscroll-in-sidebar";
// Above this width the app sidebar runs down the left edge (at and below it,
// it's a bottom bar); matches the layout's 960px breakpoint.
const SIDEBAR_BESIDE_QUERY = "(min-width: 961px)";
const SIDEBAR_POSITION_PROPERTIES = [
  "--feed-doomscroll-stack-left",
  "--feed-doomscroll-nav-top",
  "--feed-doomscroll-nav-left",
  "--feed-doomscroll-nav-width",
];
// Start loading the next page this many posts before the end, so the reader
// never lands on a spinner.
const PREFETCH_REMAINING = 3;
// Only the feed's own page frames — cards carry other lazy frames (the admin
// Hackatime breakdown) that must stay unloaded until someone opens them.
const NEXT_PAGE_SELECTOR =
  'turbo-frame[id^="home_feed_page_"][loading="lazy"][src]:not([complete]):not([busy])';
// The glide between posts: quick to leave, soft to land.
const GLIDE_DURATION = 560;
const easeOutQuint = (t) => 1 - Math.pow(1 - t, 5);
// Matches feed-doomscroll-zoom-out in _feed_doomscroll.scss.
const RETURN_DURATION = 420;
// A swipe this long, or this fast (px/ms), turns the page; shorter ones spring
// back to the post they started on.
const SWIPE_DISTANCE = 60;
const SWIPE_VELOCITY = 0.35;
// Past the first or last post, a drag moves this fraction of the finger.
const EDGE_RESISTANCE = 0.35;
// A pause this long (ms) between wheel events means a fresh flick.
const WHEEL_GESTURE_GAP = 200;

const average = (values) =>
  values.reduce((sum, value) => sum + value, 0) / (values.length || 1);

export default class extends Controller {
  static targets = ["toggle", "feed"];

  initialize() {
    this._onKeydown = this._onKeydown.bind(this);
    this._onWheel = this._onWheel.bind(this);
    this._onTouchStart = this._onTouchStart.bind(this);
    this._onTouchMove = this._onTouchMove.bind(this);
    this._onTouchEnd = this._onTouchEnd.bind(this);
    this._onResize = this._onResize.bind(this);
    this._autoplayed = new WeakSet();
    this._wheelHistory = [];
    this._index = 0;
  }

  disconnect() {
    this._teardown();
    this._finishReturn();
  }

  toggle() {
    if (this.toggleTarget.checked) {
      this._enter();
    } else {
      this._exit();
    }
  }

  // Each page arrives in a nested lazy frame; pick up its videos and keep
  // prefetching ahead of the reader. A tab switch reloads the whole feed.
  refresh(event) {
    if (!this._active) return;

    if (event?.target === this.feedTarget) {
      this._index = 0;
      this._markCurrent(this._cards()[0]);
      this.feedTarget.scrollTop = 0;
    }
    this._observeVideos();
    this._fillBackdrops();
    this._prefetch();
  }

  _enter() {
    if (this._active || !this.hasFeedTarget) return;
    this._finishReturn();

    // Open on the post the reader was already looking at, not the top.
    const cards = this._cards();
    const anchor = cards.find(
      (card) => card.getBoundingClientRect().bottom > 0,
    );

    this._active = true;
    this.element.classList.add(ACTIVE_CLASS);
    document.body.classList.add(BODY_OPEN_CLASS);
    document.addEventListener("keydown", this._onKeydown, true);
    window.addEventListener("resize", this._onResize);
    this.feedTarget.addEventListener("wheel", this._onWheel, {
      passive: false,
    });
    this.feedTarget.addEventListener("touchstart", this._onTouchStart, {
      passive: true,
    });
    this.feedTarget.addEventListener("touchmove", this._onTouchMove, {
      passive: false,
    });
    this.feedTarget.addEventListener("touchend", this._onTouchEnd);
    this.feedTarget.addEventListener("touchcancel", this._onTouchEnd);

    this.feedTarget.setAttribute("tabindex", "-1");
    this.feedTarget.focus({ preventScroll: true });

    if (!this._reducedMotion()) {
      this._videoObserver = new IntersectionObserver(
        (entries) => this._onVideoVisibility(entries),
        { root: this.feedTarget, threshold: 0.6 },
      );
      this._observeVideos();
    }

    this._placeInSidebar();
    this._fillBackdrops();
    this._index = Math.max(cards.indexOf(anchor), 0);
    this._markCurrent(cards[this._index]);
    if (cards[this._index]) {
      this.feedTarget.scrollTop = this._topOf(cards[this._index]);
    }
    this._prefetch(cards);
  }

  // Letterboxed media sits on a blurred copy of itself, as in Starscroll;
  // _feed_doomscroll.scss paints it from this property.
  _fillBackdrops() {
    this.feedTarget
      .querySelectorAll(".feed-post-card__media-slide")
      .forEach((slide) => {
        if (slide.style.getPropertyValue("--feed-doomscroll-backdrop")) return;

        const image = slide.querySelector("img");
        const src = image
          ? image.currentSrc || image.getAttribute("src")
          : slide.querySelector("video")?.getAttribute("poster");
        if (!src) return;

        slide.style.setProperty(
          "--feed-doomscroll-backdrop",
          `url(${JSON.stringify(src)})`,
        );
      });
  }

  // Lands back on the post that was on screen, zooming the normal feed out
  // from it into place.
  _exit() {
    const current = this._teardown();
    if (!current) return;

    current.scrollIntoView({ block: "start" });
    if (this._reducedMotion()) return;

    const frame = this.feedTarget.getBoundingClientRect();
    const card = current.getBoundingClientRect();
    this.feedTarget.style.setProperty(
      "--feed-doomscroll-origin-y",
      `${card.top - frame.top + card.height / 2}px`,
    );
    this.element.classList.add(RETURNING_CLASS);
    this._returnTimer = setTimeout(() => this._finishReturn(), RETURN_DURATION);
  }

  // Leaves doomscroll layout and input handling; returns the post that was on
  // screen, if any.
  _teardown() {
    if (!this._active) return null;

    const current = this._cards()[this._index];

    this._active = false;
    this._animating = false;
    this._touch = null;
    cancelAnimationFrame(this._glideFrame);
    document.removeEventListener("keydown", this._onKeydown, true);
    window.removeEventListener("resize", this._onResize);
    this.feedTarget.removeEventListener("wheel", this._onWheel);
    this.feedTarget.removeEventListener("touchstart", this._onTouchStart);
    this.feedTarget.removeEventListener("touchmove", this._onTouchMove);
    this.feedTarget.removeEventListener("touchend", this._onTouchEnd);
    this.feedTarget.removeEventListener("touchcancel", this._onTouchEnd);
    this._videoObserver?.disconnect();
    this._videoObserver = null;
    this.feedTarget.querySelectorAll(VIDEO_SELECTOR).forEach((video) => {
      if (this._autoplayed.has(video)) video.pause();
    });

    this._markCurrent(null);
    this.element.classList.remove(ACTIVE_CLASS, IN_SIDEBAR_CLASS);
    SIDEBAR_POSITION_PROPERTIES.forEach((property) =>
      this.element.style.removeProperty(property),
    );
    document.body.classList.remove(BODY_OPEN_CLASS);
    this.feedTarget.removeAttribute("tabindex");
    if (this.hasToggleTarget) this.toggleTarget.checked = false;

    return current;
  }

  _finishReturn() {
    clearTimeout(this._returnTimer);
    this.element.classList.remove(RETURNING_CLASS);
    if (this.hasFeedTarget) {
      this.feedTarget.style.removeProperty("--feed-doomscroll-origin-y");
    }
  }

  // Capture phase, so feed-keyboard (which tracks its own window-scroll
  // cursor) never acts on a post other than the one on screen.
  _onKeydown(event) {
    if (document.querySelector("dialog[open]")) return;

    if (event.key === "Escape") {
      event.preventDefault();
      this._exit();
      return;
    }

    if (this._isTyping(event) || event.metaKey || event.ctrlKey || event.altKey)
      return;

    // Space and Enter belong to a focused link or button when there is one.
    const onFeed =
      event.target === this.feedTarget || event.target === document.body;

    switch (event.key) {
      case "ArrowDown":
      case "PageDown":
      case "j":
        this._go(1);
        break;
      case "ArrowUp":
      case "PageUp":
      case "k":
        this._go(-1);
        break;
      case " ":
        if (!onFeed) return;
        this._go(event.shiftKey ? -1 : 1);
        break;
      case "l":
        this._currentCard()?.querySelector(".like-button__btn")?.click();
        break;
      case "Enter":
        if (!onFeed) {
          event.stopPropagation();
          return;
        }
        this._currentCard()?.click();
        break;
      default:
        return;
    }

    event.preventDefault();
    event.stopPropagation();
  }

  _onWheel(event) {
    if (this._ignoresInput(event)) return;
    // Sideways swipes belong to a post's media carousel.
    if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) return;
    // Let an expanded caption or quoted post scroll on its own first.
    if (this._scrollsInside(event.target, event.deltaY)) return;

    event.preventDefault();

    const magnitude = Math.abs(event.deltaY);
    const gap = event.timeStamp - (this._lastWheelAt ?? -Infinity);
    this._lastWheelAt = event.timeStamp;
    this._wheelHistory.push(magnitude);
    if (this._wheelHistory.length > 10) this._wheelHistory.shift();

    if (magnitude < 1) return;

    // A trackpad flick keeps firing ever-smaller deltas as it coasts. Only a
    // fresh gesture, or a new push that speeds the stream back up, turns the
    // page — so one flick is always exactly one post. Mid-glide only a fresh
    // flick counts (a quick second flick carries on to the next post), since
    // the rising start of the flick that began the glide also "speeds up".
    const fresh = gap > WHEEL_GESTURE_GAP;
    const history = this._wheelHistory;
    const speedingUp =
      !this._animating &&
      history.length >= 6 &&
      average(history.slice(-3)) > average(history.slice(0, -3)) * 1.2;
    if (!fresh && !speedingUp) return;

    this._go(event.deltaY > 0 ? 1 : -1);
  }

  _onTouchStart(event) {
    if (this._ignoresInput(event) || event.touches.length !== 1) return;

    // Catch a glide mid-flight: the finger takes over from where it is.
    cancelAnimationFrame(this._glideFrame);
    this._animating = false;

    const { clientX, clientY } = event.touches[0];
    this._touch = {
      startX: clientX,
      startY: clientY,
      startTop: this.feedTarget.scrollTop,
      axis: null,
      samples: [{ y: clientY, at: event.timeStamp }],
    };
  }

  _onTouchMove(event) {
    const touch = this._touch;
    if (!touch) return;

    const { clientX, clientY } = event.touches[0];
    const dx = clientX - touch.startX;
    const dy = clientY - touch.startY;

    if (!touch.axis) {
      if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
      touch.axis = Math.abs(dx) > Math.abs(dy) ? "x" : "y";
      if (touch.axis === "y" && this._scrollsInside(event.target, -dy)) {
        touch.axis = "inner";
      }
    }
    if (touch.axis !== "y") return;

    event.preventDefault();

    // The post follows the finger, with resistance past either end.
    const pastEnd =
      (dy > 0 && this._index === 0) ||
      (dy < 0 && this._index === this._cards().length - 1);
    this.feedTarget.scrollTop =
      touch.startTop - dy * (pastEnd ? EDGE_RESISTANCE : 1);

    touch.samples.push({ y: clientY, at: event.timeStamp });
    if (touch.samples.length > 4) touch.samples.shift();
  }

  _onTouchEnd() {
    const touch = this._touch;
    this._touch = null;
    if (!touch || touch.axis !== "y") return;

    const first = touch.samples[0];
    const last = touch.samples[touch.samples.length - 1];
    const distance = last.y - touch.startY;
    const velocity = (last.y - first.y) / Math.max(last.at - first.at, 1);

    const flung =
      Math.abs(distance) > SWIPE_DISTANCE ||
      Math.abs(velocity) > SWIPE_VELOCITY;
    // Finger up means the next post.
    this._go(flung ? (distance < 0 ? 1 : -1) : 0);
  }

  _onResize() {
    this._placeInSidebar();
    const current = this._currentCard();
    if (current) this.feedTarget.scrollTop = this._topOf(current);
  }

  // Beside a full-height app sidebar, the stack fills the window to its right
  // and the feed tabs sit exactly where the sidebar's own links are, which
  // step aside for them (_feed_doomscroll.scss) — so the links appear to turn
  // into the filters. The tabs stay put in the DOM so their actions still work.
  _placeInSidebar() {
    const sidebar = document.querySelector(".sidebar");
    const links = sidebar?.querySelector(".sidebar__nav-list");
    const beside = !!links && window.matchMedia(SIDEBAR_BESIDE_QUERY).matches;

    this.element.classList.toggle(IN_SIDEBAR_CLASS, beside);
    if (!beside) return;

    const bar = sidebar.getBoundingClientRect();
    const spot = links.getBoundingClientRect();
    const place = {
      "--feed-doomscroll-stack-left": bar.right,
      "--feed-doomscroll-nav-top": spot.top,
      "--feed-doomscroll-nav-left": spot.left,
      "--feed-doomscroll-nav-width": spot.width,
    };
    Object.entries(place).forEach(([property, px]) =>
      this.element.style.setProperty(property, `${px}px`),
    );
  }

  // Moves `delta` posts (0 springs back to the current one).
  _go(delta) {
    const cards = this._cards();
    if (!cards.length) return;

    this._index = Math.min(Math.max(this._index + delta, 0), cards.length - 1);
    this._markCurrent(cards[this._index]);
    this._glideTo(this._topOf(cards[this._index]));
    this._prefetch(cards);
  }

  _glideTo(target) {
    cancelAnimationFrame(this._glideFrame);

    const feed = this.feedTarget;
    const start = feed.scrollTop;
    const distance = target - start;

    if (this._reducedMotion() || Math.abs(distance) < 1) {
      feed.scrollTop = target;
      this._animating = false;
      return;
    }

    this._animating = true;
    const startedAt = performance.now();
    const step = (now) => {
      const progress = Math.min((now - startedAt) / GLIDE_DURATION, 1);
      feed.scrollTop = start + distance * easeOutQuint(progress);
      if (progress < 1) {
        this._glideFrame = requestAnimationFrame(step);
      } else {
        this._animating = false;
      }
    };
    this._glideFrame = requestAnimationFrame(step);
  }

  // Where the feed's scrollTop puts this post right under the tab bar.
  _topOf(card) {
    const padding = parseFloat(getComputedStyle(this.feedTarget).paddingTop);
    return card.offsetTop - (padding || 0);
  }

  _markCurrent(card) {
    this._currentEl?.classList.remove(CURRENT_CLASS);
    this._currentEl = card || null;
    this._currentEl?.classList.add(CURRENT_CLASS);
  }

  _prefetch(cards = this._cards()) {
    if (this._index < cards.length - PREFETCH_REMAINING) return;

    const pending = this.feedTarget.querySelector(NEXT_PAGE_SELECTOR);
    if (pending) pending.loading = "eager";
  }

  _observeVideos() {
    if (!this._videoObserver) return;
    this.feedTarget
      .querySelectorAll(VIDEO_SELECTOR)
      .forEach((video) => this._videoObserver.observe(video));
  }

  _onVideoVisibility(entries) {
    entries.forEach(({ target: video, isIntersecting }) => {
      if (isIntersecting) {
        // Browsers only allow muted autoplay; the controls let them unmute,
        // and scrolling back to a video they've unmuted keeps their choice.
        if (!this._autoplayed.has(video)) {
          video.muted = true;
          this._autoplayed.add(video);
        }
        video.play().catch(() => {});
      } else {
        video.pause();
      }
    });
  }

  // True when an element under the pointer can still scroll that way itself.
  _scrollsInside(target, deltaY) {
    for (
      let el = target;
      el && el !== this.feedTarget && el instanceof Element;
      el = el.parentElement
    ) {
      const overflowY = getComputedStyle(el).overflowY;
      if (overflowY !== "auto" && overflowY !== "scroll") continue;
      if (el.scrollHeight <= el.clientHeight + 1) continue;

      const canScroll =
        deltaY > 0
          ? el.scrollTop + el.clientHeight < el.scrollHeight - 1
          : el.scrollTop > 0;
      if (canScroll) return true;
    }
    return false;
  }

  _ignoresInput(event) {
    return (
      !this._active ||
      !!document.querySelector("dialog[open]") ||
      !!event.target.closest?.("dialog")
    );
  }

  _currentCard() {
    return this._cards()[this._index] || null;
  }

  _cards() {
    if (!this.hasFeedTarget) return [];
    return Array.from(this.feedTarget.querySelectorAll(CARD_SELECTOR)).filter(
      (card) => !card.closest(".feed-post-card__repost-preview"),
    );
  }

  _reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  _isTyping(event) {
    const tag = event.target.tagName;
    return (
      tag === "INPUT" ||
      tag === "TEXTAREA" ||
      tag === "SELECT" ||
      event.target.isContentEditable
    );
  }
}
