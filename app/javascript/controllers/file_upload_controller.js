import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "preview"];
  static values = { emptyClass: String, placeholderSelector: String };

  change() {
    const file = this.inputTarget.files?.[0];
    if (!file) return;
    this._previewImage().src = URL.createObjectURL(file);
    if (this.hasEmptyClassValue)
      this.element.classList.remove(this.emptyClassValue);
    if (this.hasPlaceholderSelectorValue) {
      const placeholder = this.element.querySelector(
        this.placeholderSelectorValue,
      );
      if (placeholder) {
        this.element.appendChild(this.inputTarget);
        this.inputTarget.hidden = true;
        placeholder.remove();
      }
    }
  }

  _previewImage() {
    if (this.hasPreviewTarget) return this.previewTarget;

    const wrapper = document.createElement("div");
    wrapper.className = "ship__upload-preview";
    const img = document.createElement("img");
    img.className = "ship__upload-image";
    img.alt = "";
    wrapper.appendChild(img);
    this.element.prepend(wrapper);
    return img;
  }
}
