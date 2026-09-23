import { Controller } from "@hotwired/stimulus";

// Keyboard layer for the review cockpit. It only clicks existing buttons, so the
// verdict logic stays in t2_decision_controller.
const HINTS = [
  ["[data-shortcut='approve']", "A"],
  ["[data-shortcut='return']", "R"],
  ["[data-shortcut='skip']", "S"],
];

const SHORTCUTS = [
  ["J / K", "Prev / next devlog"],
  ["T", "Open timelapses"],
  ["I", "Open first photo"],
  ["C", "Collapse / expand devlog"],
  ["A / R", "Approve / return"],
  ["S", "Skip to next project"],
  ["⌃ Space", "Focus feedback"],
  ["⌃ ⏎ ×2", "Record verdict (twice)"],
  ["?", "Show this help"],
];

export default class extends Controller {
  static targets = ["rail", "feedback", "legend"];

  connect() {
    this.currentIndex = 0;
    this.onKeydown = this.onKeydown.bind(this);
    document.addEventListener("keydown", this.onKeydown);
    this.decorateHints();
    this.buildLegend();
    this.observeRail();
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown);
    this.observer?.disconnect();
    this.disarmVerdict();
    this.undecorateHints();
    if (this.hasLegendTarget) this.legendTarget.innerHTML = "";
    this.dialog?.remove();
  }

  onKeydown(event) {
    if (document.querySelector(".review-cockpit__lightbox[open]")) return;

    if (this.dialog?.open) {
      if (event.key === "Escape")
        return this.consume(event, () => this.dialog.close());
      return;
    }

    // Chords never insert text, so they work while typing.
    if ((event.ctrlKey || event.metaKey) && !event.altKey) {
      if (event.code === "Space")
        return this.consume(event, () => this.focusFeedback());
      if (event.key === "Enter")
        return this.consume(event, () => this.recordVerdict());
      return;
    }

    if (event.key === "Escape") {
      const el = document.activeElement;
      if (el && el !== document.body && this.isTyping(el)) {
        return this.consume(event, () => el.blur());
      }
      return;
    }

    if (event.altKey) return;
    if (this.isTyping(event.target)) return;

    switch (event.key) {
      case "j":
        return this.consume(event, () => this.stepDevlog(1));
      case "k":
        return this.consume(event, () => this.stepDevlog(-1));
      case "t":
        return this.consume(event, () => this.openTimelapses());
      case "i":
        return this.consume(event, () => this.openPhoto());
      case "c":
        return this.consume(event, () => this.toggleDevlog());
      case "a":
        return this.consume(event, () =>
          this.click("[data-shortcut='approve']"),
        );
      case "r":
        return this.consume(event, () =>
          this.click("[data-shortcut='return']"),
        );
      case "s":
        return this.consume(event, () => this.click("[data-shortcut='skip']"));
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

  devlogEls() {
    return Array.from(this.element.querySelectorAll(".review-cockpit__devlog"));
  }

  currentDevlog() {
    return this.devlogEls()[this.currentIndex] || null;
  }

  stepDevlog(delta) {
    const els = this.devlogEls();
    if (!els.length) return;

    this.markCurrent(this.currentIndex + delta);
    this.navScrolling = true;
    this.currentDevlog()?.scrollIntoView({
      block: "nearest",
      behavior: "smooth",
    });
    clearTimeout(this.navTimer);
    this.navTimer = setTimeout(() => {
      this.navScrolling = false;
    }, 400);
  }

  markCurrent(index) {
    const els = this.devlogEls();
    if (!els.length) return;

    this.currentIndex = Math.max(0, Math.min(index, els.length - 1));
    els.forEach((el, i) =>
      el.classList.toggle(
        "review-cockpit__devlog--current",
        i === this.currentIndex,
      ),
    );
  }

  // The cursor follows the most-visible devlog, so mouse scrolling and j/k agree.
  observeRail() {
    const els = this.devlogEls();
    if (!els.length || typeof IntersectionObserver === "undefined") return;

    const root = this.hasRailTarget ? this.railTarget : null;
    this.area = new Map();
    this.observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const rect = entry.intersectionRect;
          this.area.set(
            entry.target,
            entry.isIntersecting ? rect.width * rect.height : 0,
          );
        }
        if (this.navScrolling) return;

        let best = null;
        let bestArea = 0;
        for (const [el, area] of this.area) {
          if (area > bestArea) {
            bestArea = area;
            best = el;
          }
        }
        if (best && bestArea > 0) {
          const i = this.devlogEls().indexOf(best);
          if (i !== -1 && i !== this.currentIndex) this.markCurrent(i);
        }
      },
      { root, threshold: Array.from({ length: 11 }, (_, i) => i / 10) },
    );
    els.forEach((el) => this.observer.observe(el));
    this.markCurrent(0);
  }

  openTimelapses() {
    const details = this.currentDevlog()?.querySelector(
      ".review-cockpit__devlog-recordings",
    );
    if (!details) return;

    details.open = !details.open;
    if (details.open)
      details.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }

  openPhoto() {
    this.currentDevlog()
      ?.querySelector(".review-cockpit__gallery-link")
      ?.click();
  }

  toggleDevlog() {
    this.currentDevlog()
      ?.querySelector("[data-action*='toggleDevlog']")
      ?.click();
  }

  click(selector) {
    const btn = this.element.querySelector(selector);
    if (btn && !btn.disabled) btn.click();
  }

  focusFeedback() {
    if (!this.hasFeedbackTarget) return;

    this.feedbackTarget.scrollIntoView({
      block: "nearest",
      behavior: "smooth",
    });
    this.feedbackTarget.focus();
  }

  // Recording a verdict moves money: the chord arms on the first press, fires on the second.
  recordVerdict() {
    const btn = this.element.querySelector("[data-shortcut='record']");
    if (!btn || btn.disabled) return;

    if (this.verdictArmed) {
      this.disarmVerdict();
      btn.click();
      return;
    }
    this.verdictArmed = true;
    btn.classList.add("is-armed");
    clearTimeout(this.armTimer);
    this.armTimer = setTimeout(() => this.disarmVerdict(), 1500);
  }

  disarmVerdict() {
    this.verdictArmed = false;
    clearTimeout(this.armTimer);
    this.element
      .querySelector("[data-shortcut='record']")
      ?.classList.remove("is-armed");
  }

  toggleHelp() {
    if (!this.dialog) this.buildDialog();
    if (this.dialog.open) this.dialog.close();
    else this.dialog.showModal();
  }

  buildDialog() {
    const dialog = document.createElement("dialog");
    dialog.className = "review-kbd-help";
    dialog.addEventListener("click", (e) => {
      if (e.target === dialog) dialog.close();
    });

    const rows = SHORTCUTS.map(
      ([key, desc]) =>
        `<div class="review-kbd-help__row"><kbd class="review-kbd-help__key">${key}</kbd><span class="review-kbd-help__desc">${desc}</span></div>`,
    ).join("");

    dialog.innerHTML =
      `<div class="review-kbd-help__content">` +
      `<h2 class="review-kbd-help__title">Keyboard shortcuts</h2>` +
      rows +
      `</div>`;

    document.body.appendChild(dialog);
    this.dialog = dialog;
  }

  decorateHints() {
    HINTS.forEach(([selector, label]) => {
      const el = this.element.querySelector(selector);
      if (el) this.addHint(el, label);
    });
  }

  addHint(el, label) {
    if (el.querySelector(":scope > .review-kbd-hint")) return;

    const kbd = document.createElement("kbd");
    kbd.className = "review-kbd-hint";
    kbd.textContent = label;
    el.appendChild(kbd);
  }

  undecorateHints() {
    this.element
      .querySelectorAll(".review-kbd-hint")
      .forEach((el) => el.remove());
  }

  // In the top bar rather than floating, where it covered Approve and Return.
  buildLegend() {
    if (!this.hasLegendTarget) return;

    this.legendTarget.innerHTML =
      `<span class="review-kbd-legend__title">Shortcuts</span>` +
      [
        ["J / K", "devlogs"],
        ["T", "timelapses"],
        ["?", "more"],
      ]
        .map(
          ([key, desc]) =>
            `<span class="review-kbd-legend__item"><kbd class="review-kbd-hint">${key}</kbd>${desc}</span>`,
        )
        .join("");
  }
}
