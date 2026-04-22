import { Controller } from "@hotwired/stimulus";

// Intercepts the Turbo Stream replace targeting #rsvp_counter and crossfades
// the number: the old number slides up and fades out, the new one slides in
// from below and fades in. The exiting number stays in normal flow so the
// counter's box keeps its size and baseline — the entering number is
// absolutely stacked on top, so it doesn't disturb surrounding text.
export default class extends Controller {
  connect() {
    this.prefersReducedMotion =
      window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;

    this.span = this.element.querySelector("#rsvp_counter");
    if (!this.span) return;

    this.lastCount = parseInt(this.span.dataset.count, 10) || 0;
    this.animating = false;
    this.queue = [];
    this.build(this.span.textContent.trim());

    this._onStream = this.onStream.bind(this);
    document.addEventListener("turbo:before-stream-render", this._onStream);
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this._onStream);
  }

  build(text) {
    this.span.textContent = "";
    this.span.setAttribute("aria-label", text);
    const inner = document.createElement("span");
    inner.className = "rsvp-counter__inner";
    inner.textContent = text;
    this.span.appendChild(inner);
    this.currentInner = inner;
  }

  onStream(event) {
    const stream = event.target;
    if (stream?.getAttribute?.("target") !== "rsvp_counter") return;

    const template = stream.querySelector("template");
    const incoming = template?.content.querySelector("#rsvp_counter");
    if (!incoming) return;

    const newCount = parseInt(incoming.dataset.count, 10);
    if (Number.isNaN(newCount)) return;
    const newText = incoming.textContent.trim();

    event.preventDefault();

    if (newCount === this.lastCount) return;

    if (newCount < this.lastCount) {
      this.lastCount = newCount;
      this.build(newText);
      return;
    }

    this.lastCount = newCount;
    this.enqueue(newText);
  }

  enqueue(newText) {
    if (this.animating) {
      this.queue.push(newText);
    } else {
      this.animate(newText);
    }
  }

  animate(newText) {
    this.animating = true;
    this.pulse();

    if (this.prefersReducedMotion) {
      this.build(newText);
      this.animating = false;
      this.drain();
      return;
    }

    const oldInner = this.currentInner;
    oldInner.classList.add("rsvp-counter__inner--exiting");

    const newInner = document.createElement("span");
    newInner.className = "rsvp-counter__inner rsvp-counter__inner--entering";
    newInner.textContent = newText;
    this.span.appendChild(newInner);

    // Wait for the entering animation to finish; the exiting one has the
    // same duration so its cleanup rides along.
    newInner.addEventListener(
      "animationend",
      () => {
        oldInner.remove();
        newInner.classList.remove("rsvp-counter__inner--entering");
        this.span.setAttribute("aria-label", newText);
        this.currentInner = newInner;
        this.animating = false;
        this.drain();
      },
      { once: true }
    );
  }

  drain() {
    if (this.queue.length > 0) {
      this.animate(this.queue.shift());
    }
  }

  pulse() {
    this.span.classList.remove("rsvp-counter--tick");
    void this.span.offsetWidth;
    this.span.classList.add("rsvp-counter--tick");
  }
}
