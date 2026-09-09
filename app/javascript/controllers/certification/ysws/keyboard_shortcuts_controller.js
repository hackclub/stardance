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
//   e            jump to the review-decision panel (focus minutes)
//   a / r        approve / reject the current devlog
//   - / shift+-  decrease approved minutes by 15 / 30
//   t            open the current devlog's lapse recordings in the lightbox
//   ctrl+space   focus the current devlog's internal-notes box
//   ?            toggle the keyboard-shortcut help overlay (Escape closes)

// Per-control hint badges: [selector within a devlog, key label]. The decision
// panel title (E) and notes label (⌃Space) are placed separately in decorateHints.
const HINTS = [
  [".btn-approve", "A"],
  [".btn-reject", "R"],
  ['.adjust-btn[data-adjust-action="-15"]', "−"],
  ['.adjust-btn[data-adjust-action="-30"]', "⇧−"],
];

// Rows for the ? help overlay.
const SHORTCUTS = [
  ["J / K", "Prev / next devlog"],
  ["E", "Jump to decision"],
  ["A / R", "Approve / reject"],
  ["− / ⇧−", "Cut 15 / 30 min"],
  ["T", "Open lapse recordings"],
  ["⌃ Space", "Focus internal notes"],
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
    this.clearHighlight();
    this.undecorateHints();
    this.legend?.remove();
    this.dialog?.remove();
  }

  onKeydown(event) {
    // The help overlay is modal: Escape closes it and nothing else fires.
    if (this.dialog?.open) {
      if (event.key === "Escape") return this.consume(event, () => this.dialog.close());
      return;
    }

    // ctrl/⌘ + space focuses the current devlog's internal-notes box. It's a
    // chord (never inserts text), so it works even while typing elsewhere and is
    // handled before the plain-key guards below.
    if ((event.ctrlKey || event.metaKey) && !event.altKey && event.code === "Space") {
      return this.consume(event, () => this.openNotes());
    }

    // Escape drops focus out of a field (e.g. the internal-notes box opened with
    // ctrl+space, or the minutes input) so the reviewer can jump back to the
    // single-key shortcuts. Handled before the typing guard so it fires while a
    // field is focused.
    if (event.key === "Escape") {
      const el = document.activeElement;
      if (el && el !== document.body && this.element.contains(el) && typeof el.blur === "function") {
        return this.consume(event, () => el.blur());
      }
      return;
    }

    // Ctrl/Meta/Alt combos are left to the browser (Escape aside — unused here
    // but kept explicit); single-key shortcuts must never fight text entry.
    if (event.ctrlKey || event.metaKey || event.altKey) return;
    if (this.isTyping(event.target)) return;

    switch (event.key) {
      case "j": return this.consume(event, () => this.stepDevlog(1));
      case "k": return this.consume(event, () => this.stepDevlog(-1));
      case "e": return this.consume(event, () => this.openDecision());
      case "a": return this.consume(event, () => this.clickCurrent(".btn-approve"));
      case "r": return this.consume(event, () => this.clickCurrent(".btn-reject"));
      case "-": return this.consume(event, () => this.adjustTime("-15"));
      case "_": return this.consume(event, () => this.adjustTime("-30"));
      case "t": return this.consume(event, () => this.openLapses());
      case "?": return this.consume(event, () => this.toggleHelp());
    }
  }

  consume(event, fn) {
    event.preventDefault();
    fn();
  }

  isTyping(el) {
    if (!el) return false;
    return ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName) || el.isContentEditable;
  }

  // ── Devlog navigation ──────────────────────────────────────────────────
  // Only the current review's (non-frozen) cards carry the decision controls, so
  // navigation, the verdict/time/lapse keys, and the cursor all operate on these.
  // Frozen prior-review cards render first in the DOM; including them made the
  // cursor land on a card with no buttons, so a/r/e appeared to do nothing.
  devlogEls() {
    return Array.from(this.element.querySelectorAll(".devlog-item:not(.devlog-item--frozen)"));
  }

  currentDevlog() {
    return this.devlogEls()[this.currentIndex] || null;
  }

  stepDevlog(delta) {
    this.setDevlog(this.currentIndex + delta);
  }

  // Update the cursor WITHOUT scrolling — shared by keyboard nav (which then
  // scrolls) and the scroll observer (which must not).
  markCurrent(index) {
    const els = this.devlogEls();
    if (!els.length) return;
    this.currentIndex = Math.max(0, Math.min(index, els.length - 1));
    els.forEach((el, i) => el.classList.toggle("devlog-item--kbd-active", i === this.currentIndex));
  }

  // j/k: move the cursor and float the card to the top of the viewport.
  setDevlog(index) {
    this.markCurrent(index);
    this.devlogEls()[this.currentIndex]?.scrollIntoView({ block: "start", behavior: "smooth" });
  }

  // Track the top-most visible devlog so the verdict/time/lapse keys act on the
  // card the reviewer has SCROLLED to, not only the one j/k last moved to —
  // otherwise the cursor and the viewport drift apart and the keys feel random.
  observeScroll() {
    const els = this.devlogEls();
    if (!els.length || typeof IntersectionObserver === "undefined") return;
    this.visible = new Set();
    this.observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) this.visible.add(entry.target);
        else this.visible.delete(entry.target);
      }
      const list = this.devlogEls();
      const topMost = list.find((el) => this.visible.has(el)); // DOM order = visual order
      if (topMost) {
        const i = list.indexOf(topMost);
        if (i !== this.currentIndex) this.markCurrent(i);
      }
    }, { root: null, rootMargin: "0px 0px -60% 0px", threshold: 0 });
    els.forEach((el) => this.observer.observe(el));
  }

  clearHighlight() {
    this.element
      .querySelectorAll(".devlog-item--kbd-active")
      .forEach((el) => el.classList.remove("devlog-item--kbd-active"));
  }

  // ── Actions on the current devlog ───────────────────────────────────────
  // "e" brings the current devlog's decision panel into view. It deliberately
  // does NOT focus a field: focusing an input trips the typing guard and would
  // swallow the a/r verdict keys the reviewer reaches for next.
  openDecision() {
    const panel = this.currentDevlog()?.querySelector(".devlog-review-panel");
    panel?.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  // Click a control on the current devlog if present and enabled. The devlog
  // controller autosaves; single-press is fine since these are reversible.
  clickCurrent(selector) {
    const devlog = this.currentDevlog();
    if (!devlog) return;
    const btn = devlog.querySelector(selector);
    if (btn && !btn.disabled) btn.click();
  }

  adjustTime(delta) {
    this.clickCurrent(`.adjust-btn[data-adjust-action="${delta}"]`);
  }

  // Open the current devlog's first recording tile — this hands off to the
  // recording-gallery slice, which owns the JKL lightbox. Fall back to the
  // page-level recordings card when the current devlog has no footage.
  openLapses() {
    const devlog = this.currentDevlog();
    const tile =
      devlog?.querySelector(".devlog-recordings-section .recording-gallery__item") ||
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
      const title = devlog.querySelector(".devlog-review-panel .panel-title");
      if (title) this.addHint(title, "E");
      const notes = devlog.querySelector(".notes-textarea");
      const notesLabel = notes?.closest(".panel-section")?.querySelector(".panel-label");
      if (notesLabel) this.addHint(notesLabel, "⌃Space");
    });
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
      [["J / K", "devlogs"], ["T", "lapses"], ["?", "more"]]
        .map(([key, desc]) => `<span class="ysws-kbd-legend__item"><kbd class="kbd-hint">${key}</kbd>${desc}</span>`)
        .join("");
    document.body.appendChild(legend);
    this.legend = legend;
  }
}
