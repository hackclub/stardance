import { Controller } from "@hotwired/stimulus";

// Toggles read/edit mode on the user profile. The actual bio editor lives in
// bio_editor_controller; this controller only swaps button states and reveals
// the editor + banner upload affordances.
export default class extends Controller {
  static targets = [
    "bioView",
    "bioEdit",
    "editBtn",
    "saveBtn",
    "cancelBtn",
    "banner",
    "bannerLabel",
    "bannerInput",
    "placeholder",
  ];
  static classes = ["editing"];
  static values = { defaultBanner: String };

  connect() {
    this._originalBanner = this.bannerTarget.src;
    this._onSubmitEnd = this._onSubmitEnd.bind(this);
    this.element.addEventListener("turbo:submit-end", this._onSubmitEnd);
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-end", this._onSubmitEnd);
  }

  enter(event) {
    event?.preventDefault();
    this.element.classList.add(this.editingClass);
    this._toggleHidden(this.editBtnTarget, true);
    this._toggleHidden(this.saveBtnTarget, false);
    this._toggleHidden(this.cancelBtnTarget, false);
    if (this.hasBioEditTarget) this.bioEditTarget.hidden = false;
    if (this.hasBioViewTarget) this.bioViewTarget.hidden = true;
  }

  cancel(event) {
    event?.preventDefault();
    this.element.classList.remove(this.editingClass);
    this._toggleHidden(this.editBtnTarget, false);
    this._toggleHidden(this.saveBtnTarget, true);
    this._toggleHidden(this.cancelBtnTarget, true);
    if (this.hasBioEditTarget) this.bioEditTarget.hidden = true;
    if (this.hasBioViewTarget) this.bioViewTarget.hidden = false;

    // Revert banner preview
    this.bannerTarget.src = this._originalBanner;
    if (this.hasBannerInputTarget) this.bannerInputTarget.value = "";
  }

  previewBanner() {
    const file = this.bannerInputTarget.files?.[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    this.bannerTarget.src = url;
    const banner = this.element.querySelector(".profile__banner");
    if (banner) banner.classList.remove("profile__banner--empty");
    if (this.hasPlaceholderTarget) {
      banner.appendChild(this.bannerInputTarget);
      this.bannerInputTarget.hidden = true;
      this.placeholderTarget.remove();
    }
  }

  _onSubmitEnd(event) {
    if (!event.detail.success) return;
    this._originalBanner = this.bannerTarget.src;
    this.element.classList.remove(this.editingClass);
    this._toggleHidden(this.editBtnTarget, false);
    this._toggleHidden(this.saveBtnTarget, true);
    this._toggleHidden(this.cancelBtnTarget, true);
    if (this.hasBioEditTarget) this.bioEditTarget.hidden = true;
    if (this.hasBioViewTarget) this.bioViewTarget.hidden = false;
  }

  _toggleHidden(el, hidden) {
    if (!el) return;
    el.hidden = hidden;
  }
}
