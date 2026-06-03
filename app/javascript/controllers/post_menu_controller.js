import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["menu"];
  static values = {
    url: String,
    postId: Number,
    projectId: Number,
    source: String,
    feedRequestId: String,
  };

  connect() {
    this._onClickOutside = this._onClickOutside.bind(this);
    this._onKeydown = this._onKeydown.bind(this);
  }

  disconnect() {
    document.removeEventListener("click", this._onClickOutside);
    document.removeEventListener("keydown", this._onKeydown);
  }

  toggle(event) {
    event.stopPropagation();

    if (this.menuTarget.hidden) {
      this._open();
    } else {
      this._close();
    }
  }

  share(event) {
    event.preventDefault();
    const url = new URL(this.urlValue, window.location.origin).href;

    navigator.clipboard.writeText(url).then(() => {
      const button = event.currentTarget;
      const original = button.textContent;
      button.textContent = "Copied!";
      setTimeout(() => {
        button.textContent = original;
      }, 1500);
    });

    this._close();
  }

  notInterested(event) {
    event.preventDefault();

    this._sendFeedback("not_interested");
    this._close();
    this.element.closest(".feed-post-card")?.remove();
  }

  // private

  _sendFeedback(eventType) {
    const body = JSON.stringify({
      events: [
        {
          event_type: eventType,
          item_type: "post",
          post_id: this.postIdValue,
          project_id: this.hasProjectIdValue ? this.projectIdValue : null,
          source: this.sourceValue || "post_menu",
          feed_request_id: this.feedRequestIdValue,
        },
      ],
    });

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

  _open() {
    this.menuTarget.hidden = false;
    document.addEventListener("click", this._onClickOutside);
    document.addEventListener("keydown", this._onKeydown);
  }

  _close() {
    this.menuTarget.hidden = true;
    document.removeEventListener("click", this._onClickOutside);
    document.removeEventListener("keydown", this._onKeydown);
  }

  _onClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this._close();
    }
  }

  _onKeydown(event) {
    if (event.key === "Escape") {
      this._close();
    }
  }
}
