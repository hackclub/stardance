import { Controller } from "@hotwired/stimulus";

const ACCEPTED_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
  "image/heic",
  "image/heif",
];

export default class extends Controller {
  static targets = ["dropZone", "fileInput", "preview", "placeholder"];

  #file = null;
  #url = null;

  disconnect() {
    this.#revokeUrl();
  }

  // ── Event handlers ────────────────────────────────────────────────────────

  select() {
    this.#setFile(this.fileInputTarget.files[0]);
  }

  drop(event) {
    event.preventDefault();
    this.dropZoneTarget.classList.remove("image-dropzone--dragover");
    const file = event.dataTransfer.files[0];
    if (file) this.#setFile(file);
  }

  dragover(event) {
    event.preventDefault();
    this.dropZoneTarget.classList.add("image-dropzone--dragover");
  }

  dragleave() {
    this.dropZoneTarget.classList.remove("image-dropzone--dragover");
  }

  remove(event) {
    event.preventDefault();
    this.#file = null;
    this.#revokeUrl();
    this.#syncInput();
    this.#render();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  #setFile(file) {
    if (!file || !ACCEPTED_TYPES.includes(file.type)) return;
    this.#revokeUrl();
    this.#file = file;
    this.#render();
    this.#syncInput();
  }

  #render() {
    if (!this.#file) {
      this.previewTarget.hidden = true;
      this.placeholderTarget.hidden = false;
      return;
    }

    this.#url = URL.createObjectURL(this.#file);
    const img = this.previewTarget.querySelector(
      ".image-dropzone__preview-img",
    );
    img.src = this.#url;
    img.alt = this.#file.name;
    this.previewTarget.hidden = false;
    this.placeholderTarget.hidden = true;
  }

  #syncInput() {
    const dt = new DataTransfer();
    if (this.#file) dt.items.add(this.#file);
    this.fileInputTarget.files = dt.files;
  }

  #revokeUrl() {
    if (this.#url) {
      URL.revokeObjectURL(this.#url);
      this.#url = null;
    }
  }
}
