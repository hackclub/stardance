import { Controller } from "@hotwired/stimulus";

// Native HTML5 drag-reorder gated by a `data-sortable-handle` element so plain
// row clicks don't start drags. POSTs the new id order to `urlValue` on drop.
export default class extends Controller {
  static targets = ["item"];
  static values = { url: String };

  connect() {
    this.dragging = null;
    this.armedItem = null;

    this.disarm = this.disarm.bind(this);
    this.onDragStart = this.onDragStart.bind(this);
    this.onDragOver = this.onDragOver.bind(this);
    this.onDragEnd = this.onDragEnd.bind(this);

    this.itemTargets.forEach((item) => this.wireItem(item));

    document.addEventListener("mouseup", this.disarm);
    document.addEventListener("touchend", this.disarm);
    document.addEventListener("touchcancel", this.disarm);
  }

  disconnect() {
    document.removeEventListener("mouseup", this.disarm);
    document.removeEventListener("touchend", this.disarm);
    document.removeEventListener("touchcancel", this.disarm);
  }

  wireItem(item) {
    item.setAttribute("draggable", "false");

    item.addEventListener("dragstart", this.onDragStart);
    item.addEventListener("dragover", this.onDragOver);
    item.addEventListener("dragend", this.onDragEnd);

    item.querySelectorAll("[data-sortable-handle]").forEach((handle) => {
      const arm = () => this.arm(item);
      handle.addEventListener("mousedown", arm);
      handle.addEventListener("touchstart", arm, { passive: true });
    });
  }

  arm(item) {
    if (this.armedItem && this.armedItem !== item) {
      this.armedItem.setAttribute("draggable", "false");
    }
    item.setAttribute("draggable", "true");
    this.armedItem = item;
  }

  disarm() {
    // Defer disarm so dragstart still fires in browsers that re-check
    // draggable mid-gesture, and click-without-drag still ends as not-draggable.
    if (this.armedItem && !this.dragging) {
      const target = this.armedItem;
      setTimeout(() => {
        if (target !== this.dragging) target.setAttribute("draggable", "false");
      }, 0);
      this.armedItem = null;
    }
  }

  onDragStart(event) {
    const item = event.currentTarget;
    if (item.getAttribute("draggable") !== "true") {
      event.preventDefault();
      return;
    }
    this.dragging = item;
    item.classList.add("is-dragging");
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", item.dataset.id || "");
  }

  onDragOver(event) {
    if (!this.dragging) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";

    const target = event.currentTarget;
    if (!target || target === this.dragging) return;

    const rect = target.getBoundingClientRect();
    const midpoint = rect.top + rect.height / 2;
    if (event.clientY < midpoint) {
      target.parentNode.insertBefore(this.dragging, target);
    } else {
      target.parentNode.insertBefore(this.dragging, target.nextSibling);
    }
  }

  onDragEnd() {
    if (this.dragging) {
      this.dragging.classList.remove("is-dragging");
      this.dragging.setAttribute("draggable", "false");
    }
    const wasDragging = !!this.dragging;
    this.dragging = null;
    this.armedItem = null;
    if (wasDragging) this.commitOrder();
  }

  commitOrder() {
    if (!this.hasUrlValue || !this.urlValue) return;

    const order = this.itemTargets.map((el) => el.dataset.id).filter(Boolean);
    const tokenEl = document.querySelector('meta[name="csrf-token"]');

    fetch(this.urlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": tokenEl?.getAttribute("content") || "",
      },
      body: JSON.stringify({ order: order }),
    }).catch(() => {});
  }
}
