import { Controller } from "@hotwired/stimulus";

const SAFE_PATTERN = /^[a-zA-Z0-9_-]+$/;

export default class extends Controller {
  static targets = ["input", "feedback", "submit", "counter"];
  static values = {
    url: String,
    debounce: { type: Number, default: 350 },
    max: { type: Number, default: 30 },
    checkOnConnect: { type: Boolean, default: false },
  };

  connect() {
    this.lastQuery = null;
    this.abortController = null;
    this.timer = null;
    this._initialValue = this.checkOnConnectValue
      ? null
      : this.inputTarget.value;
    this._setSubmitDisabled(true);
    this._updateCounter();
    if (this.checkOnConnectValue && this.inputTarget.value.trim() !== "") {
      this.check();
    }
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer);
    if (this.abortController) this.abortController.abort();
  }

  onInput() {
    if (this.timer) clearTimeout(this.timer);
    this._updateCounter();

    if (this.inputTarget.value === this._initialValue) {
      this._setState("available", "");
      return;
    }

    this._setState("checking", "Checking\u2026");
    this.timer = setTimeout(() => this.check(), this.debounceValue);
  }

  async check() {
    const value = this.inputTarget.value.trim();
    if (value === this.lastQuery) return;
    this.lastQuery = value;

    if (value === "") {
      this._setState("empty", "");
      return;
    }

    if (!SAFE_PATTERN.test(value)) {
      this._setState(
        "invalid",
        "Only letters, numbers, hyphens, and underscores allowed.",
      );
      return;
    }

    if (value.length > this.maxValue) {
      this._setState("too_long", `Keep it under ${this.maxValue} characters.`);
      return;
    }

    this._setState("checking", "Checking\u2026");

    if (this.abortController) this.abortController.abort();
    this.abortController = new AbortController();

    try {
      const url = new URL(this.urlValue, window.location.origin);
      url.searchParams.set("display_name", value);
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal,
        credentials: "same-origin",
      });
      if (!res.ok) return;
      const data = await res.json();
      if (this.inputTarget.value.trim() !== value) return;
      this._setState(data.status, data.message || "");
    } catch (err) {
      if (err.name !== "AbortError") {
        this._setState("error", "");
      }
    }
  }

  _setState(status, message) {
    if (this.hasFeedbackTarget) {
      this.feedbackTarget.textContent = message;
      this.feedbackTarget.dataset.status = status;
    }
    this.element.dataset.status = status;
    this._setSubmitDisabled(status !== "available");
  }

  _setSubmitDisabled(disabled) {
    if (!this.hasSubmitTarget) return;
    this.submitTarget.disabled = disabled;
    this.submitTarget.classList.toggle(
      "special-action-btn--disabled",
      disabled,
    );
  }

  _updateCounter() {
    if (!this.hasCounterTarget) return;
    const len = this.inputTarget.value.length;
    this.counterTarget.textContent = `${len}/${this.maxValue}`;
    this.counterTarget.dataset.status = len > this.maxValue ? "over" : "ok";
  }
}
