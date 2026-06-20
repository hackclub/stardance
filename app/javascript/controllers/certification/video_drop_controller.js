import { Controller } from "@hotwired/stimulus";
import { DirectUpload } from "@rails/activestorage";

// Drag-and-drop video input with immediate Active Storage direct upload.
// Picking or dropping a file starts the upload right away (not on form
// submit), with a progress bar tracking the transfer. The controller lives on
// the verdict form (not the drop zone) so it can also lock the submit button
// until the upload finishes; the form then posts the blob's signed id instead
// of the raw bytes. Client checks mirror the server rules
// (Certification::Ship), so a file the model would reject gets caught here
// with a message instead of a silent failure.
const ACCEPTED = ["video/mp4", "video/webm", "video/quicktime"];

export default class extends Controller {
  static targets = [
    "zone",
    "input",
    "prompt",
    "preview",
    "video",
    "filename",
    "status",
    "progressWrapper",
    "progressBar",
    "submitBtn",
  ];
  static classes = ["over", "uploading", "done", "error"];
  static values = { directUploadUrl: String };

  open() {
    this.inputTarget.click();
  }

  over(event) {
    event.preventDefault();
    this.zoneTarget.classList.add(this.overClass);
  }

  leave(event) {
    event.preventDefault();
    this.zoneTarget.classList.remove(this.overClass);
  }

  drop(event) {
    event.preventDefault();
    this.zoneTarget.classList.remove(this.overClass);

    const file = event.dataTransfer.files?.[0];
    if (!file) return;

    const data = new DataTransfer();
    data.items.add(file);
    this.inputTarget.files = data.files;
    this.accept(file);
  }

  change() {
    const file = this.inputTarget.files?.[0];
    if (file) this.accept(file);
  }

  accept(file) {
    const problem = this.validate(file);
    if (problem) return this.reject(problem);

    this.revoke();
    this.objectUrl = URL.createObjectURL(file);
    this.videoTarget.src = this.objectUrl;
    this.filenameTarget.textContent = file.name;

    this.zoneTarget.classList.remove(this.errorClass, this.doneClass);
    this.promptTarget.hidden = true;
    this.previewTarget.hidden = false;

    this.startUpload(file);
  }

  startUpload(file) {
    // Replacing the video mid-upload starts a new transfer; the token makes
    // the superseded upload's callbacks no-ops so it can't clobber the new
    // one's progress or blob field.
    const token = (this.uploadToken = (this.uploadToken || 0) + 1);
    this.blobField?.remove();
    this.blobField = null;

    this.setUploading(true);
    this.setProgress(0);
    this.statusTarget.textContent = "Uploading… 0%";

    const upload = new DirectUpload(file, this.directUploadUrlValue, this);
    upload.create((error, blob) => {
      if (token !== this.uploadToken) return;

      if (error) {
        this.reject(`Upload failed: ${error}`);
        return;
      }

      this.inputTarget.value = "";
      const hiddenField = document.createElement("input");
      hiddenField.type = "hidden";
      hiddenField.name = this.inputTarget.name;
      hiddenField.value = blob.signed_id;
      this.element.appendChild(hiddenField);
      this.blobField = hiddenField;

      this.setUploading(false);
      this.zoneTarget.classList.add(this.doneClass);
      this.statusTarget.textContent = `✓ Uploaded — ${this.mb(file.size)}`;
    });
  }

  directUploadWillStoreFileWithXHR(xhr) {
    const token = this.uploadToken;
    xhr.upload.addEventListener("progress", (event) => {
      if (token !== this.uploadToken) return;
      if (event.lengthComputable) {
        const pct = Math.round((event.loaded / event.total) * 100);
        this.setProgress(pct);
        this.statusTarget.textContent = `Uploading… ${pct}%`;
      }
    });
  }

  // Belt and braces with the disabled submit button: blocks Enter-key and
  // any other submit path while a transfer is in flight.
  guardSubmit(event) {
    if (this.uploading) event.preventDefault();
  }

  reject(message) {
    this.uploadToken = (this.uploadToken || 0) + 1;
    this.inputTarget.value = "";
    this.revoke();
    this.blobField?.remove();
    this.blobField = null;
    this.zoneTarget.classList.remove(this.doneClass);
    this.zoneTarget.classList.add(this.errorClass);
    this.previewTarget.hidden = true;
    this.promptTarget.hidden = false;
    this.statusTarget.textContent = message;
    this.setUploading(false);
  }

  validate(file) {
    if (!ACCEPTED.includes(file.type)) {
      return "That's not a supported video. Use mp4, webm, or mov.";
    }
    return null;
  }

  setProgress(pct) {
    this.progressWrapperTarget.hidden = false;
    this.progressWrapperTarget.setAttribute("aria-valuenow", pct);
    this.progressBarTarget.style.width = `${pct}%`;
  }

  setUploading(uploading) {
    this.uploading = uploading;
    this.zoneTarget.classList.toggle(this.uploadingClass, uploading);
    if (!uploading) this.progressWrapperTarget.hidden = true;

    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = uploading;
    }
  }

  mb(bytes) {
    return `${(bytes / 1024 / 1024).toFixed(0)} MB`;
  }

  revoke() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl);
    this.objectUrl = null;
  }

  disconnect() {
    this.revoke();
  }
}
