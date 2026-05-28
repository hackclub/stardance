import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dialog"];

  connect() {
    this._boundBackdropClick = this.backdropClick.bind(this);
    this.element.addEventListener("click", this._boundBackdropClick);

    if (this.element.tagName === "DIALOG") {
      this._heldBodyOverflow = false;
      this._previousBodyOverflow = "";
      this._syncBodyScrollLock = () => {
        if (this.element.open && !this._heldBodyOverflow) {
          this._previousBodyOverflow = document.body.style.overflow;
          document.body.style.overflow = "hidden";
          this._heldBodyOverflow = true;
        } else if (!this.element.open && this._heldBodyOverflow) {
          document.body.style.overflow = this._previousBodyOverflow;
          this._heldBodyOverflow = false;
        }
      };
      this._dialogObserver = new MutationObserver(this._syncBodyScrollLock);
      this._dialogObserver.observe(this.element, {
        attributes: true,
        attributeFilter: ["open"],
      });
      this._syncBodyScrollLock();
    }

    this.openSettingsModalFromQueryParam();
  }

  disconnect() {
    this.element.removeEventListener("click", this._boundBackdropClick);
    if (this._dialogObserver) {
      this._dialogObserver.disconnect();
      this._dialogObserver = null;
      if (this._heldBodyOverflow) {
        document.body.style.overflow = this._previousBodyOverflow;
        this._heldBodyOverflow = false;
      }
    }
  }

  open(event) {
    event.preventDefault();
    if (!this.hasDialogTarget) return;
    if (typeof this.dialogTarget.showModal === "function") {
      this.dialogTarget.showModal();
    } else {
      // Fallback for the rare browser without <dialog> support.
      this.dialogTarget.setAttribute("open", "");
    }
  }

  close(event) {
    event?.preventDefault();
    if (this.hasDialogTarget) {
      if (typeof this.dialogTarget.close === "function") {
        this.dialogTarget.close();
      } else {
        this.dialogTarget.removeAttribute("open");
      }
      return;
    }

    if (this.element.tagName === "DIALOG") {
      this.element.close();
      document.body.style.overflow = "";
    }
  }

  backdropClick(event) {
    if (this.element.tagName !== "DIALOG") {
      if (event.target === this.element) this.close();
      return;
    }

    // A real backdrop click on a <dialog> fires with event.target === the
    // dialog itself. Clicks on inner content (including synthetic ones from
    // things like fileInput.click(), which bubble up at coords 0,0) have
    // event.target on the descendant — never treat those as backdrop hits.
    if (event.target !== this.element) return;

    const rect = this.element.getBoundingClientRect();
    const clickedInside =
      event.clientX >= rect.left &&
      event.clientX <= rect.right &&
      event.clientY >= rect.top &&
      event.clientY <= rect.bottom;

    if (!clickedInside) this.close();
  }

  openSettingsModalFromQueryParam() {
    if (this.element.id !== "settings-modal") return;

    const params = new URLSearchParams(window.location.search);
    const settingsParam = params.get("settings");
    if (!["1", "true"].includes(settingsParam)) return;

    if (!this.element.open) {
      this.element.showModal();
    }

    params.delete("settings");
    const query = params.toString();
    const nextUrl = `${window.location.pathname}${query ? `?${query}` : ""}${
      window.location.hash
    }`;
    window.history.replaceState(window.history.state, "", nextUrl);
  }
}
