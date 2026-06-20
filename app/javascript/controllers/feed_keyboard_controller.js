import { Controller } from "@hotwired/stimulus";

const CARD_SELECTOR = "article.feed-post-card";

const SHORTCUTS = [
  ["j", "Next post"],
  ["k", "Previous post"],
  ["l", "Like post"],
  ["enter", "Open post"],
  ["?", "Show keyboard shortcuts"],
];

export default class extends Controller {
  connect() {
    this._activeIndex = -1;
    this._boundKeydown = this._onKeydown.bind(this);
    document.addEventListener("keydown", this._boundKeydown);
  }

  disconnect() {
    document.removeEventListener("keydown", this._boundKeydown);
    this._clearHighlight();
    this._dialog?.remove();
  }

  _onKeydown(event) {
    if (this._dialog?.open && event.key === "Escape") {
      event.preventDefault();
      this._dialog.close();
      return;
    }

    if (this._isTyping(event)) return;
    if (event.metaKey || event.ctrlKey || event.altKey) return;

    switch (event.key) {
      case "j":
        event.preventDefault();
        this._move(1);
        break;
      case "k":
        event.preventDefault();
        this._move(-1);
        break;
      case "l":
        event.preventDefault();
        this._likeActive();
        break;
      case "Enter":
        event.preventDefault();
        this._openActive();
        break;
      case "?":
        event.preventDefault();
        this._toggleHelp();
        break;
    }
  }

  _move(delta) {
    const cards = this._cards();
    if (!cards.length) return;

    this._clearHighlight();

    const next = this._activeIndex + delta;
    if (next < 0 || next >= cards.length) return;

    this._activeIndex = next;
    const card = cards[this._activeIndex];
    card.classList.add("feed-post-card--kbd-active");
    const y = card.getBoundingClientRect().top + window.scrollY - 16;
    window.scrollTo({ top: y, behavior: "instant" });
  }

  _likeActive() {
    const cards = this._cards();
    const card = cards[this._activeIndex];
    if (!card) return;

    const likeBtn = card.querySelector(".like-button__btn");
    if (likeBtn) likeBtn.click();
  }

  _openActive() {
    const cards = this._cards();
    const card = cards[this._activeIndex];
    if (!card) return;

    const link = card.querySelector(".feed-post-card__overlay-link");
    if (link) {
      link.click();
    }
  }

  _toggleHelp() {
    if (!this._dialog) this._buildDialog();
    if (this._dialog.open) {
      this._dialog.close();
    } else {
      this._dialog.showModal();
    }
  }

  _buildDialog() {
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
    this._dialog = dialog;
  }

  _clearHighlight() {
    this.element
      .querySelectorAll(".feed-post-card--kbd-active")
      .forEach((el) => el.classList.remove("feed-post-card--kbd-active"));
  }

  _cards() {
    return Array.from(this.element.querySelectorAll(CARD_SELECTOR)).filter(
      (card) => !card.closest(".feed-post-card__repost-preview"),
    );
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
