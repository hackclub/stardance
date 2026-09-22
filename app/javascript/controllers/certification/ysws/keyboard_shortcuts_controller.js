import { Controller } from "@hotwired/stimulus";

// Flag-gated (:ysws_review_shortcuts) keyboard layer for the YSWS review page.
// Mirrors the hardware cockpit's keybinding technique — a single document
// keydown maintains a "current devlog" cursor and dispatches shortcuts to the
// existing per-devlog controls. It only clicks buttons that already exist
// (approve/reject/adjust) and opens the lapse lightbox owned by the recording-
// gallery slice by clicking its first tile; no JS coupling with that controller.
//
// When active it also decorates the controls it drives with on-screen <kbd>
// hint badges and pins a compact legend for the navigation keys, so the
// shortcuts are discoverable without opening the ? help overlay.
//
//   j / k        next / previous devlog (clamped)
//   a / r        approve / reject the current devlog
//   5 / 2        set approved minutes to 50% / 25%
//   + / shift++  add 15 / 30 min        - / shift+-  cut 15 / 30 min
//   t            open the current devlog's lapse recordings in the lightbox
//   ctrl+space   focus the current devlog's internal-notes box
//   ctrl+enter   complete the review (press twice to confirm)
//   ?            toggle the keyboard-shortcut help overlay (Escape closes)

// Per-control hint badges: [selector within a devlog, key label]. The notes
// label (⌃Space) and the page-level Complete button (⌃⏎) are placed separately
// in decorateHints.
const HINTS = [
  [".btn-approve", "A"],
  [".btn-reject", "R"],
  ['.adjust-btn[data-adjust-action="50%"]', "5"],
  ['.adjust-btn[data-adjust-action="25%"]', "2"],
  ['.adjust-btn[data-adjust-action="-15"]', "−"],
  ['.adjust-btn[data-adjust-action="-30"]', "⇧−"],
];

// Rows for the ? help overlay.
const SHORTCUTS = [
  ["J / K", "Prev / next devlog"],
  ["A / R", "Approve / reject"],
  ["5 / 2", "Set 50% / 25%"],
  ["+ / ⇧+", "Add 15 / 30 min"],
  ["− / ⇧−", "Cut 15 / 30 min"],
  ["T", "Open lapse recordings"],
  ["⌃ Space", "Focus internal notes"],
  ["⌃ ⏎ ×2", "Complete review (twice)"],
  ["?", "Show this help"],
];

export default class extends Controller {
  connect() {
    this.currentIndex = 0;
    this.onKeydown = this.onKeydown.bind(this);
    document.addEventListener("keydown", this.onKeydown);
    this.decorateHints();
    this.buildLegend();
    this.observeScroll();
    this.markCurrent(0);
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown);
    this.observer?.disconnect();
    this.endNavScroll();
    this.disarmComplete();
    this.undecorateHints();
    this.legend?.remove();
    this.dialog?.remove();
  }

  onKeydown(event) {
    // The lapse lightbox (opened with `t`) is modal and owns the keyboard while
    // open — its own controller handles JKL/Escape. Stand down entirely so our
    // j/k/a/r don't drive the review or double-scrub behind it. We don't consume
    // the event, so it flows on to the lapse player's document listener.
    if (document.querySelector(".lapse-player__lightbox")) return;

    // The help overlay is modal: Escape closes it and nothing else fires.
    if (this.dialog?.open) {
      if (event.key === "Escape")
        return this.consume(event, () => this.dialog.close());
      return;
    }

    // ctrl/⌘ + space focuses the current devlog's internal-notes box. It's a
    // chord (never inserts text), so it works even while typing elsewhere and is
    // handled before the plain-key guards below.
    if (
      (event.ctrlKey || event.metaKey) &&
      !event.altKey &&
      event.code === "Space"
    ) {
      return this.consume(event, () => this.openNotes());
    }

    // ctrl/⌘ + Enter completes the review — a deliberate chord (works even while
    // typing) that arms on the first press and confirms on the second, so a
    // stray keystroke can never finalize the whole review.
    if (
      (event.ctrlKey || event.metaKey) &&
      !event.altKey &&
      event.key === "Enter"
    ) {
      return this.consume(event, () => this.completeReview());
    }

    // Escape drops focus out of a field (e.g. the internal-notes box opened with
    // ctrl+space, or the minutes input) so the reviewer can jump back to the
    // single-key shortcuts. Handled before the typing guard so it fires while a
    // field is focused.
    if (event.key === "Escape") {
      const el = document.activeElement;
      if (
        el &&
        el !== document.body &&
        this.element.contains(el) &&
        typeof el.blur === "function"
      ) {
        return this.consume(event, () => el.blur());
      }
      return;
    }

    // Ctrl/Meta/Alt combos are left to the browser (Escape aside — unused here
    // but kept explicit); single-key shortcuts must never fight text entry.
    if (event.ctrlKey || event.metaKey || event.altKey) return;
    if (this.isTyping(event.target)) return;

    switch (event.key) {
      case "j":
        return this.consume(event, () => this.stepDevlog(1));
      case "k":
        return this.consume(event, () => this.stepDevlog(-1));
      case "a":
        return this.consume(event, () => this.clickCurrent(".btn-approve"));
      case "r":
        return this.consume(event, () => this.clickCurrent(".btn-reject"));
      case "5":
        return this.consume(event, () => this.adjustTime("50%"));
      case "2":
        return this.consume(event, () => this.adjustTime("25%"));
      case "=":
        return this.consume(event, () => this.adjustMinutes(15));
      case "+":
        return this.consume(event, () => this.adjustMinutes(30));
      case "-":
        return this.consume(event, () => this.adjustTime("-15"));
      case "_":
        return this.consume(event, () => this.adjustTime("-30"));
      case "t":
        return this.consume(event, () => this.openLapses());
      case "?":
        return this.consume(event, () => this.toggleHelp());
    }
  }

  consume(event, fn) {
    event.preventDefault();
    fn();
  }

  isTyping(el) {
    if (!el) return false;
    return (
      ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName) ||
      el.isContentEditable
    );
  }

  // ── Devlog navigation ──────────────────────────────────────────────────
  // Only the current review's (non-frozen) cards carry the decision controls, so
  // navigation, the verdict/time/lapse keys, and the cursor all operate on these.
  // Frozen prior-review cards render first in the DOM; including them made the
  // cursor land on a card with no buttons, so a/r/e appeared to do nothing.
  devlogEls() {
    return Array.from(
      this.element.querySelectorAll(".devlog-item:not(.devlog-item--frozen)"),
    );
  }

  currentDevlog() {
    return this.devlogEls()[this.currentIndex] || null;
  }

  stepDevlog(delta) {
    this.setDevlog(this.currentIndex + delta);
  }

  // Track which devlog is current (clamped). Kept as an internal cursor for the
  // nav/verdict/lapse keys; there's no visual highlight — it read as noise.
  markCurrent(index) {
    const els = this.devlogEls();
    if (!els.length) return;
    this.currentIndex = Math.max(0, Math.min(index, els.length - 1));
  }

  // j/k: move the cursor and smoothly scroll the card into view. The smooth
  // animation re-fires the observer, so we suspend its re-selection until the
  // scroll actually ends (see beginNavScroll) — otherwise it drags the cursor
  // back to the still-visible previous card mid-animation.
  setDevlog(index) {
    this.markCurrent(index);
    this.beginNavScroll();
    this.devlogEls()[this.currentIndex]?.scrollIntoView({
      block: "start",
      behavior: "smooth",
    });
  }

  // Suspend observer re-selection until the programmatic smooth scroll finishes.
  // scrollend is authoritative; the timeout is a fallback for browsers that don't
  // emit it, or when the target is already in place (no scroll → no scrollend).
  beginNavScroll() {
    this.navScrolling = true;
    clearTimeout(this.navScrollTimeout);
    if (this.onScrollEnd)
      window.removeEventListener("scrollend", this.onScrollEnd);
    this.onScrollEnd = () => this.endNavScroll();
    window.addEventListener("scrollend", this.onScrollEnd, { once: true });
    // scrollend never fires when the target is already in place (no scroll), which
    // would freeze cursor-follow for the whole fallback. Probe once: if the page
    // hasn't moved shortly after, there's nothing to wait for — lift immediately;
    // otherwise keep a bounded fallback for browsers that don't emit scrollend.
    const startY = window.scrollY;
    this.navScrollTimeout = setTimeout(() => {
      if (window.scrollY === startY) this.endNavScroll();
      else this.navScrollTimeout = setTimeout(() => this.endNavScroll(), 900);
    }, 150);
  }

  endNavScroll() {
    this.navScrolling = false;
    clearTimeout(this.navScrollTimeout);
    if (this.onScrollEnd) {
      window.removeEventListener("scrollend", this.onScrollEnd);
      this.onScrollEnd = null;
    }
  }

  // The "current" devlog follows whichever Review Decision panel is on screen the
  // most — that's the card the reviewer is actually working on. We track each
  // non-frozen panel's visible area and pick the largest.
  observeScroll() {
    const panels = this.reviewPanels();
    if (!panels.length || typeof IntersectionObserver === "undefined") return;
    this.panelArea = new Map(); // panel element -> visible pixel area
    this.observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const rect = entry.intersectionRect;
          this.panelArea.set(
            entry.target,
            entry.isIntersecting ? rect.width * rect.height : 0,
          );
        }
        // Don't re-select while a keyboard nav's smooth scroll is still running —
        // that scroll is what fires this callback, and reacting to it fights j/k.
        if (this.navScrolling) return;
        let best = null;
        let bestArea = 0;
        for (const [panel, area] of this.panelArea) {
          if (area > bestArea) {
            bestArea = area;
            best = panel;
          }
        }
        if (best && bestArea > 0) {
          const i = this.devlogEls().indexOf(best.closest(".devlog-item"));
          if (i !== -1 && i !== this.currentIndex) this.markCurrent(i);
        }
      },
      { root: null, threshold: Array.from({ length: 21 }, (_, i) => i / 20) },
    );
    panels.forEach((panel) => this.observer.observe(panel));
  }

  // The Review Decision panel for each non-frozen devlog, in devlogEls() order.
  reviewPanels() {
    return this.devlogEls()
      .map((item) => item.querySelector(".devlog-review-panel"))
      .filter(Boolean);
  }

  // ── Actions on the current devlog ───────────────────────────────────────
  // Click a control on the current devlog if present and enabled. The devlog
  // controller autosaves; single-press is fine since these are reversible.
  clickCurrent(selector) {
    const devlog = this.currentDevlog();
    if (!devlog) return;
    const btn = devlog.querySelector(selector);
    if (btn && !btn.disabled) btn.click();
  }

  // Click one of the current devlog's quick-adjust buttons (50% / 25% / -15 / -30).
  adjustTime(delta) {
    this.clickCurrent(`.adjust-btn[data-adjust-action="${delta}"]`);
  }

  // Increase the current devlog's approved minutes: there's no +button, so bump
  // the input directly and fire `input` so the devlog controller saves + updates
  // the hours display, matching how the quick-adjust buttons feed it.
  adjustMinutes(delta) {
    const input = this.currentDevlog()?.querySelector(".minutes-input");
    if (!input || input.disabled) return;
    const current = parseInt(input.value, 10);
    input.value = Math.max(0, (Number.isNaN(current) ? 0 : current) + delta);
    input.dispatchEvent(new Event("input", { bubbles: true }));
  }

  // Complete the whole review. Destructive + irreversible, so it's armed on the
  // first press (with a visual cue) and only fires on a second press within the
  // window — a keyboard "are you sure?".
  completeReview() {
    const btn = this.element.querySelector(".btn-complete");
    if (!btn || btn.disabled) return;
    if (this.completeArmed) {
      this.disarmComplete();
      btn.click();
      return;
    }
    this.completeArmed = true;
    btn.classList.add("btn-complete--armed");
    clearTimeout(this.completeArmTimer);
    this.completeArmTimer = setTimeout(() => this.disarmComplete(), 1500);
  }

  disarmComplete() {
    this.completeArmed = false;
    clearTimeout(this.completeArmTimer);
    this.element
      .querySelector(".btn-complete")
      ?.classList.remove("btn-complete--armed");
  }

  // Open the current devlog's first recording tile — this hands off to the
  // recording-gallery slice, which owns the JKL lightbox. Fall back to the
  // page-level recordings card when the current devlog has no footage.
  openLapses() {
    const devlog = this.currentDevlog();
    const tile =
      devlog?.querySelector(
        ".devlog-recordings-section .recording-gallery__item",
      ) ||
      this.element.querySelector(".recordings-card .recording-gallery__item");
    if (tile) tile.click();
  }

  // ── Help overlay ────────────────────────────────────────────────────────
  toggleHelp() {
    if (!this.dialog) this.buildDialog();
    if (this.dialog.open) this.dialog.close();
    else this.dialog.showModal();
  }

  buildDialog() {
    const dialog = document.createElement("dialog");
    dialog.className = "kbd-help";
    dialog.addEventListener("click", (e) => {
      if (e.target === dialog) dialog.close();
    });

    const rows = SHORTCUTS.map(
      ([key, desc]) =>
        `<div class="kbd-help__row"><kbd class="kbd-help__key">${key}</kbd><span class="kbd-help__desc">${desc}</span></div>`,
    ).join("");

    dialog.innerHTML =
      `<div class="kbd-help__content">` +
      `<h2 class="kbd-help__title">Keyboard shortcuts</h2>` +
      rows +
      `</div>`;

    document.body.appendChild(dialog);
    this.dialog = dialog;
  }

  // ctrl+space: bring the current devlog's notes box into view and focus it.
  openNotes() {
    const devlog = this.currentDevlog();
    const notes = devlog?.querySelector(".notes-textarea");
    if (!notes || notes.disabled) return;
    notes.scrollIntoView({ block: "nearest", behavior: "smooth" });
    notes.focus();
  }

  // ── On-screen hint badges + legend ──────────────────────────────────────
  // Tag each control a key drives with a small <kbd> badge, and pin a legend
  // for the keys that aren't attached to a single button (j/k nav, t, ?).
  decorateHints() {
    this.devlogEls().forEach((devlog) => {
      if (devlog.classList.contains("devlog-item--frozen")) return;
      HINTS.forEach(([selector, label]) => {
        const el = devlog.querySelector(selector);
        if (el) this.addHint(el, label);
      });
      const notes = devlog.querySelector(".notes-textarea");
      const notesLabel = notes
        ?.closest(".panel-section")
        ?.querySelector(".panel-label");
      if (notesLabel) this.addHint(notesLabel, "⌃Space");
    });
    // Page-level Complete button (double-tap ctrl+enter), placed once outside the loop.
    const complete = this.element.querySelector(".btn-complete");
    if (complete) this.addHint(complete, "⌃⏎");
  }

  addHint(el, label) {
    if (el.querySelector(":scope > .kbd-hint")) return; // already decorated
    const kbd = document.createElement("kbd");
    kbd.className = "kbd-hint";
    kbd.textContent = label;
    el.appendChild(kbd);
  }

  undecorateHints() {
    this.element.querySelectorAll(".kbd-hint").forEach((el) => el.remove());
  }

  buildLegend() {
    const legend = document.createElement("div");
    legend.className = "ysws-kbd-legend";
    legend.innerHTML =
      `<span class="ysws-kbd-legend__title">Shortcuts</span>` +
      [
        ["J / K", "devlogs"],
        ["T", "lapses"],
        ["?", "more"],
      ]
        .map(
          ([key, desc]) =>
            `<span class="ysws-kbd-legend__item"><kbd class="kbd-hint">${key}</kbd>${desc}</span>`,
        )
        .join("");
    document.body.appendChild(legend);
    this.legend = legend;
  }
}
