import { Controller } from "@hotwired/stimulus";

const DEVLOG_URL = /\/projects\/[^/]+\/devlogs\/\d+/;

// Opens a post in a modal. The clicked feed card is cloned as an inert
// placeholder for instant paint; the turbo frame then loads the server-rendered
// card (same media variant, so images come from browser cache) plus comments,
// and the placeholder is dropped when the frame renders.
export default class extends Controller {
  static targets = ["dialog", "cardSlot", "frame"];

  connect() {
    this._loadingHTML = this.frameTarget.innerHTML;
    this._scrollY = 0;
    this._movedFlashes = [];
    this._onClose = () => this._restoreScroll();
    this.dialogTarget.addEventListener("close", this._onClose);
  }

  disconnect() {
    this.dialogTarget.removeEventListener("close", this._onClose);
    this._flashObserver?.disconnect();
  }

  open(event) {
    const url = event.detail?.url;
    // Cards that don't link to a devlog (e.g. shop suggestions) fall through
    // to card-link's normal navigation.
    if (!url || !DEVLOG_URL.test(url)) return;

    event.preventDefault();

    const card = event.target.closest("[data-controller~='card-link']");
    if (card) {
      const clone = card.cloneNode(true);
      clone.inert = true;
      // Duplicate ids from the clone must not shadow the live card for the
      // brief time the placeholder is on screen (turbo streams target by id).
      clone.querySelectorAll("[id]").forEach((el) => el.removeAttribute("id"));
      clone.removeAttribute("id");
      // Cosmetic parity with the server-rendered card that replaces it:
      // full body text, no read-more or comment buttons.
      clone
        .querySelector(".feed-post-card__body--clamped")
        ?.classList.remove("feed-post-card__body--clamped");
      clone.querySelector(".feed-post-card__read-more")?.remove();
      clone.querySelector(".feed-post-card__comment-action")?.remove();
      this.cardSlotTarget.replaceChildren(clone);
    }

    this._focusComments = Boolean(event.detail.comments);

    const params = new URLSearchParams();
    if (card?.dataset.mediaVariant) {
      params.set("media_variant", card.dataset.mediaVariant);
    }
    if (card?.dataset.postId) params.set("panel_post", card.dataset.postId);
    const query = params.toString();
    this.frameTarget.src = query
      ? `${url}${url.includes("?") ? "&" : "?"}${query}`
      : url;

    // The modal makes the page inert, which would leave a playing feed video
    // audible but uncontrollable.
    document.querySelectorAll("video").forEach((video) => video.pause());

    this._scrollY = window.scrollY;
    document.body.style.position = "fixed";
    document.body.style.top = `-${this._scrollY}px`;
    document.body.style.width = "100%";
    this.dialogTarget.showModal();
    this._watchFlashes();
  }

  close() {
    this.dialogTarget.close();
  }

  // The placeholder leaves as the frame's card renders, so both are never
  // visible at once.
  clearPlaceholder() {
    this.cardSlotTarget.replaceChildren();
  }

  // Any successful form submission inside the frame (comment, like, repost)
  // reloads it: turbo-stream responses target the feed card behind the panel
  // (first id match), so the panel re-renders itself to stay in sync. A comment
  // draft survives reloads triggered by other forms.
  frameSubmitted(event) {
    if (!event.detail.success) return;

    const form = event.detail.formSubmission?.formElement;
    const textarea = this._commentTextarea();
    if (textarea?.value && form && !form.contains(textarea)) {
      this._draft = textarea.value;
    }
    this.frameTarget.reload();
  }

  frameLoaded() {
    this._dedupeIds();

    const textarea = this._commentTextarea();
    if (this._draft && textarea) textarea.value = this._draft;
    this._draft = null;

    if (this._focusComments) {
      this._focusComments = false;
      textarea?.focus();
    }
  }

  trackPress(event) {
    this._pressOnBackdrop =
      event.target === this.dialogTarget && !this._insideDialog(event);
  }

  // Only close when both the press and the release happened on the backdrop,
  // so a text-selection drag that ends outside the panel doesn't dismiss it.
  backdropClick(event) {
    if (event.target !== this.dialogTarget) return;
    if (this._insideDialog(event)) return;
    if (!this._pressOnBackdrop) return;

    this.close();
  }

  _commentTextarea() {
    return this.frameTarget.querySelector(".devlog-detail__comment-textarea");
  }

  // Ids the server-rendered panel card shares with the feed card behind the
  // panel are dropped from the panel copy, keeping turbo-stream targets
  // unambiguous. Panel-only ids (comment threads, form fields) survive.
  _dedupeIds() {
    this.frameTarget.querySelectorAll("[id]").forEach((el) => {
      const matches = document.querySelectorAll(`[id="${CSS.escape(el.id)}"]`);
      if (matches.length > 1 && matches[0] !== el) el.removeAttribute("id");
    });
  }

  // Flash toasts render in #flash-region, underneath the dialog's top layer;
  // while the panel is open, new ones are adopted into the dialog so they
  // stay visible, then returned on close.
  _watchFlashes() {
    const region = document.getElementById("flash-region");
    if (!region) return;

    this._flashObserver?.disconnect();
    this._flashObserver = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType !== Node.ELEMENT_NODE) return;
          this.dialogTarget.appendChild(node);
          this._movedFlashes.push(node);
        });
      });
    });
    this._flashObserver.observe(region, { childList: true });
  }

  _insideDialog(event) {
    const rect = this.dialogTarget.getBoundingClientRect();
    return (
      event.clientX >= rect.left &&
      event.clientX <= rect.right &&
      event.clientY >= rect.top &&
      event.clientY <= rect.bottom
    );
  }

  _restoreScroll() {
    document.body.style.position = "";
    document.body.style.top = "";
    document.body.style.width = "";
    window.scrollTo(0, this._scrollY);

    this._flashObserver?.disconnect();
    this._flashObserver = null;
    const region = document.getElementById("flash-region");
    this._movedFlashes.forEach((node) => {
      if (region && node.parentElement === this.dialogTarget) {
        region.appendChild(node);
      }
    });
    this._movedFlashes = [];

    this.cardSlotTarget.replaceChildren();
    this.frameTarget.removeAttribute("src");
    this.frameTarget.innerHTML = this._loadingHTML;
    this._draft = null;
    this._focusComments = false;
  }
}
