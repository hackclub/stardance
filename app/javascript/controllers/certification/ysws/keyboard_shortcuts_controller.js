import { Controller } from "@hotwired/stimulus";
import { bindings, chordFromEvent, label, modified } from "./shortcut_bindings";
import ShortcutSettings from "./shortcut_settings";

// Flag-gated (:ysws_review_shortcuts) keyboard layer for the YSWS review page.
// The server supplies the shared catalog and this user's account preferences.
// Actions use existing controls so authorization, saves and audit paths agree.

export default class extends Controller {
  static values = {
    catalog: Object,
    settings: Object,
    reserved: Array,
    url: String,
  };

  connect() {
    this.currentIndex = 0;
    this.isMac = /Mac|iPhone|iPad/.test(navigator.platform);
    this.editor = new ShortcutSettings(this);
    this.onKeydown = this.onKeydown.bind(this);
    document.addEventListener("keydown", this.onKeydown);
    this.lastFocusedControl = null;
    this.onFocusIn = (event) => {
      if (event.target === this.lastFocusedControl) return;
      const card = event.target.closest(".devlog-item");
      const index = this.devlogEls().indexOf(card);
      if (index !== -1) {
        this.lastFocusedControl = event.target;
        this.markCurrent(index);
      }
    };
    this.onPointerDown = (event) => {
      if (event.button !== 0) return;
      const index = this.devlogEls().indexOf(
        event.target.closest(".devlog-item"),
      );
      if (index !== -1) this.markCurrent(index);
    };
    this.element.addEventListener("focusin", this.onFocusIn);
    this.element.addEventListener("pointerdown", this.onPointerDown);
    this.onPointerMove = this.onPointerMove.bind(this);
    this.pointerPosition = null;
    document.addEventListener("pointermove", this.onPointerMove);
    this.refreshHints();
    this.markCurrent(0);
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown);
    this.element.removeEventListener("focusin", this.onFocusIn);
    this.element.removeEventListener("pointerdown", this.onPointerDown);
    document.removeEventListener("pointermove", this.onPointerMove);
    this.disarmComplete();
    this.undecorateHints();
    this.legend?.remove();
    this.editor.destroy();
  }

  onKeydown(event) {
    if (
      event.defaultPrevented ||
      event.isComposing ||
      event.keyCode === 229 ||
      ["Dead", "Process", "Unidentified"].includes(event.key) ||
      event.getModifierState("AltGraph")
    )
      return;
    if (this.editor.open) {
      if (event.repeat) return;
      return this.editor.keydown(event);
    }
    if (
      document.querySelector(
        ".lapse-player__lightbox, dialog[open], .fraud-report-modal.is-open, .return-ship-cert-modal.is-open, .media-viewer-modal.is-open",
      )
    ) {
      this.disarmComplete();
      return;
    }

    if (event.key === "Escape") {
      const el = document.activeElement;
      if (el && this.element.contains(el) && typeof el.blur === "function") {
        event.preventDefault();
        el.blur();
      }
      this.disarmComplete();
      return;
    }

    const notes = this.focusedNotes();
    const key = chordFromEvent(event);
    const effective = bindings(
      this.catalogValue,
      this.settingsValue,
      this.isMac,
      Boolean(notes),
    );
    const action = Object.keys(effective).find((id) =>
      effective[id].includes(key),
    );
    if (!action) return;
    // Preserve the existing deliberate focus/complete chords in other fields;
    // new verdict, time and navigation chords are restricted to internal notes.
    if (
      this.isTyping(event.target) &&
      !notes &&
      (!["notes", "complete"].includes(action) || !modified(key))
    )
      return;
    // Suppress native repeat actions too (e.g. Control+K deleting Mac text).
    if (event.repeat) {
      event.preventDefault();
      return;
    }
    // A focused note always wins over the pointer-selected card.
    if (notes)
      this.markCurrent(this.devlogEls().indexOf(notes.closest(".devlog-item")));
    if (action !== "complete") this.disarmComplete();
    const selector = this.catalogValue[action].selector;
    if (selector) {
      const button = this.currentDevlog()?.querySelector(selector);
      if (!button || button.disabled) return;
      event.preventDefault();
      button.click();
      return;
    }
    event.preventDefault();
    switch (action) {
      case "next":
        this.stepDevlog(1, Boolean(notes));
        break;
      case "previous":
        this.stepDevlog(-1, Boolean(notes));
        break;
      case "add15":
        this.adjustMinutes(15);
        break;
      case "add30":
        this.adjustMinutes(30);
        break;
      case "recordings":
        this.openLapses();
        break;
      case "notes":
        this.openNotes();
        break;
      case "complete":
        this.completeReview();
        break;
      case "help":
        this.editor.show();
        break;
    }
  }

  focusedNotes() {
    const el = document.activeElement;
    return el?.matches(".notes-textarea:not(:disabled)") &&
      this.element.contains(el) &&
      el.closest(".devlog-item:not(.devlog-item--frozen)")
      ? el
      : null;
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

  stepDevlog(delta, focusNotes = false) {
    this.setDevlog(this.currentIndex + delta);
    if (focusNotes) this.openNotes();
  }

  // Track which devlog is current (clamped). Kept as an internal cursor for the
  // nav/verdict/lapse keys; there's no visual highlight — it read as noise.
  markCurrent(index) {
    const els = this.devlogEls();
    if (!els.length) return;
    this.currentIndex = Math.max(0, Math.min(index, els.length - 1));
  }

  // Keyboard navigation remains selected until the pointer actually moves.
  setDevlog(index) {
    this.markCurrent(index);
    this.devlogEls()[this.currentIndex]?.scrollIntoView({
      block: "start",
      behavior: "smooth",
    });
  }

  onPointerMove(event) {
    if (event.pointerType !== "mouse") return;
    const previous = this.pointerPosition;
    this.pointerPosition = { x: event.clientX, y: event.clientY };
    if (previous?.x === event.clientX && previous?.y === event.clientY) return;
    if (
      event.buttons ||
      this.isTyping(document.activeElement) ||
      this.editor.open ||
      document.querySelector(
        ".lapse-player__lightbox, dialog[open], .fraud-report-modal.is-open, .return-ship-cert-modal.is-open, .media-viewer-modal.is-open",
      )
    )
      return;
    const card = event.target.closest(".devlog-item");
    const index = this.devlogEls().indexOf(card);
    // Margins, floating controls and frozen cards leave the last target alone.
    if (index !== -1) this.markCurrent(index);
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
    if (!tile) return;
    tile.click();
  }

  // ctrl+space: bring the current devlog's notes box into view and focus it.
  openNotes() {
    const devlog = this.currentDevlog();
    const notes = devlog?.querySelector(".notes-textarea");
    if (!notes || notes.disabled) return;
    notes.scrollIntoView({ block: "nearest", behavior: "smooth" });
    notes.focus();
  }

  refreshHints() {
    this.undecorateHints();
    this.legend?.remove();
    this.disarmComplete();
    const keys = bindings(this.catalogValue, this.settingsValue);
    const hint = (id) => {
      const preferred =
        this.isMac && id !== "notes"
          ? keys[id].find((key) => key.startsWith("meta+"))
          : null;
      const key = preferred || keys[id][0];
      return key ? label(key) : "";
    };
    this.devlogEls().forEach((devlog) => {
      Object.entries(this.catalogValue).forEach(([id, action]) => {
        const el = action.selector && devlog.querySelector(action.selector);
        if (el && hint(id)) this.addHint(el, hint(id));
      });
      const notes = devlog.querySelector(".notes-textarea");
      const notesLabel = notes
        ?.closest(".panel-section")
        ?.querySelector(".panel-label");
      if (notesLabel && hint("notes")) this.addHint(notesLabel, hint("notes"));
    });
    const complete = this.element.querySelector(".btn-complete");
    if (complete && hint("complete"))
      this.addHint(complete, `${hint("complete")} ×2`);
    this.buildLegend();
  }

  addHint(el, label) {
    if (el.querySelector(":scope > .kbd-hint")) return; // already decorated
    const kbd = document.createElement("kbd");
    kbd.className = "kbd-hint";
    kbd.textContent = label;
    kbd.setAttribute("data-turbo-temporary", "");
    el.appendChild(kbd);
  }

  undecorateHints() {
    this.element.querySelectorAll(".kbd-hint").forEach((el) => el.remove());
  }

  buildLegend() {
    const legend = document.createElement("button");
    legend.type = "button";
    legend.className = "ysws-kbd-legend";
    legend.textContent = "Shortcuts";
    legend.setAttribute("data-turbo-temporary", "");
    legend.setAttribute("aria-haspopup", "dialog");
    const keys = bindings(this.catalogValue, this.settingsValue).help;
    if (keys.length) this.addHint(legend, keys.map(label).join(" / "));
    legend.addEventListener("click", () => {
      this.disarmComplete();
      this.editor.show();
    });
    document.body.appendChild(legend);
    this.legend = legend;
  }
}
