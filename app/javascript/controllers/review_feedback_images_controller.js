import { Controller } from "@hotwired/stimulus";

// Multi-image picker for the hardware funding review form. Previews the
// reviewer's selected feedback photos, lets them drop or remove files, and
// keeps the file input in sync so the current selection submits with the
// verdict. Server-side validation (image type / size / count) is the source of
// truth; this only mirrors the accepted types and max count for a nicer UI.
export default class extends Controller {
  static targets = ["input", "grid", "dropZone"];
  static values = { max: { type: Number, default: 6 } };

  #files = [];
  #urls = [];

  disconnect() {
    this.#revokeUrls();
  }

  select() {
    this.#addFiles(this.inputTarget.files);
  }

  drop(event) {
    event.preventDefault();
    this.#toggleDragover(false);
    this.#addFiles(event.dataTransfer.files);
  }

  dragover(event) {
    event.preventDefault();
    this.#toggleDragover(true);
  }

  dragleave() {
    this.#toggleDragover(false);
  }

  removeFile({ params: { index } }) {
    this.#files.splice(index, 1);
    this.#render();
  }

  #toggleDragover(on) {
    if (this.hasDropZoneTarget)
      this.dropZoneTarget.classList.toggle(
        "review-form__image-drop--dragover",
        on,
      );
  }

  #acceptedTypes() {
    return (this.inputTarget.accept || "")
      .split(",")
      .map((type) => type.trim())
      .filter(Boolean);
  }

  #addFiles(fileList) {
    const accepted = this.#acceptedTypes();
    const incoming = Array.from(fileList).filter(
      (file) => accepted.length === 0 || accepted.includes(file.type),
    );
    const room = this.maxValue - this.#files.length;
    this.#files.push(...incoming.slice(0, Math.max(0, room)));
    this.#render();
  }

  #render() {
    this.#revokeUrls();
    this.gridTarget.innerHTML = "";

    if (this.#files.length === 0) {
      this.gridTarget.hidden = true;
      this.#syncInput();
      return;
    }

    this.gridTarget.hidden = false;
    this.#files.forEach((file, index) => {
      const item = document.createElement("li");
      item.className = "review-form__image-preview";

      const url = URL.createObjectURL(file);
      this.#urls.push(url);
      const img = document.createElement("img");
      img.src = url;
      img.alt = file.name;
      img.className = "review-form__image-preview-media";
      item.appendChild(img);

      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "review-form__image-preview-remove";
      remove.setAttribute("aria-label", "Remove image");
      remove.textContent = "×";
      remove.dataset.action = "review-feedback-images#removeFile";
      remove.dataset.reviewFeedbackImagesIndexParam = String(index);
      item.appendChild(remove);

      this.gridTarget.appendChild(item);
    });

    this.#syncInput();
  }

  #syncInput() {
    const data = new DataTransfer();
    this.#files.forEach((file) => data.items.add(file));
    this.inputTarget.files = data.files;
  }

  #revokeUrls() {
    this.#urls.forEach((url) => URL.revokeObjectURL(url));
    this.#urls = [];
  }
}
