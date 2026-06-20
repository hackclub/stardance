import { Controller } from "@hotwired/stimulus";

// Standard tooltip. Attach to the element that should reveal it; the popover is
// rendered into <body> and positioned relative to the element. Supports an
// optional bold title above the message.
//
// Hover-capable pointers reveal on hover/focus; coarse-pointer (touch) devices
// fall back to tap-to-toggle, since hover semantics don't apply there.
export default class extends Controller {
  static values = {
    title: String,
    message: String,
    position: { type: String, default: "top" },
  };

  connect() {
    this.boundShow = this.show.bind(this);
    this.boundHide = this.hide.bind(this);
    this.boundKey = this.handleKey.bind(this);
    this.boundReposition = this.reposition.bind(this);
    this.boundOutsideClick = this.handleOutsideClick.bind(this);

    this.hoverCapable = window.matchMedia?.("(hover: hover)")?.matches ?? false;

    if (this.hoverCapable) {
      this.element.addEventListener("mouseenter", this.boundShow);
      this.element.addEventListener("mouseleave", this.boundHide);
      this.element.addEventListener("focusin", this.boundShow);
      this.element.addEventListener("focusout", this.boundHide);
    } else {
      this.element.addEventListener("click", this.toggle);
    }
  }

  disconnect() {
    if (this.hoverCapable) {
      this.element.removeEventListener("mouseenter", this.boundShow);
      this.element.removeEventListener("mouseleave", this.boundHide);
      this.element.removeEventListener("focusin", this.boundShow);
      this.element.removeEventListener("focusout", this.boundHide);
    } else {
      this.element.removeEventListener("click", this.toggle);
    }
    this.hide();
  }

  toggle = () => {
    if (this.popover) this.hide();
    else this.show();
  };

  show() {
    if (this.popover) return;

    this.popover = document.createElement("div");
    this.popover.className = `tooltip tooltip--${this.positionValue}`;
    this.popover.setAttribute("role", "tooltip");

    if (this.titleValue) {
      const title = document.createElement("strong");
      title.className = "tooltip__title";
      title.textContent = this.titleValue;
      this.popover.appendChild(title);
    }
    this.popover.appendChild(document.createTextNode(this.messageValue));

    this.#container().appendChild(this.popover);

    this.reposition();

    requestAnimationFrame(() => {
      if (this.popover) this.popover.classList.add("tooltip--visible");
    });

    // Deferred so the opening tap doesn't immediately trip the outside-click.
    setTimeout(() => {
      document.addEventListener("click", this.boundOutsideClick);
      document.addEventListener("keydown", this.boundKey);
      window.addEventListener("scroll", this.boundReposition, {
        passive: true,
      });
      window.addEventListener("resize", this.boundReposition, {
        passive: true,
      });
    }, 0);
  }

  hide() {
    document.removeEventListener("click", this.boundOutsideClick);
    document.removeEventListener("keydown", this.boundKey);
    window.removeEventListener("scroll", this.boundReposition);
    window.removeEventListener("resize", this.boundReposition);

    if (this.popover) {
      this.popover.remove();
      this.popover = null;
    }
  }

  reposition() {
    if (!this.popover) return;
    const rect = this.element.getBoundingClientRect();
    const pop = this.popover.getBoundingClientRect();
    const gap = 12;
    let top, left;

    switch (this.positionValue) {
      case "bottom":
        top = rect.bottom + gap;
        left = rect.left + rect.width / 2 - pop.width / 2;
        break;
      case "left":
        top = rect.top + rect.height / 2 - pop.height / 2;
        left = rect.left - pop.width - gap;
        break;
      case "right":
        top = rect.top + rect.height / 2 - pop.height / 2;
        left = rect.right + gap;
        break;
      case "top":
      default:
        top = rect.top - pop.height - gap;
        left = rect.left + rect.width / 2 - pop.width / 2;
        break;
    }

    const container = this.#container();
    if (container !== document.body) {
      const cr = container.getBoundingClientRect();
      top -= cr.top;
      left -= cr.left;
    }

    this.popover.style.top = `${Math.max(8, top)}px`;
    this.popover.style.left = `${Math.max(8, left)}px`;
  }

  handleOutsideClick(event) {
    if (this.element.contains(event.target)) return;
    if (this.popover && this.popover.contains(event.target)) return;
    this.hide();
  }

  handleKey(event) {
    if (event.key === "Escape") this.hide();
  }

  #container() {
    const dialog = this.element.closest("dialog[open]");
    return dialog || document.body;
  }
}
