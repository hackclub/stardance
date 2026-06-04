import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["slot", "preview", "removeFlag"];

  replacePreview({ target }) {
    const slot = target.closest("[data-devlog-edit-target='slot']");
    const preview = slot.querySelector("[data-devlog-edit-target='preview']");
    const removeFlag = slot.querySelector(
      "[data-devlog-edit-target='removeFlag']",
    );
    const file = target.files[0];
    if (!file) return;

    removeFlag.disabled = false;

    const url = URL.createObjectURL(file);
    if (file.type.startsWith("video/")) {
      preview.innerHTML = `<video src="${url}" controls class="devlog-edit__attachment-media"></video>`;
    } else {
      preview.innerHTML = `<img src="${url}" alt="" class="devlog-edit__attachment-media">`;
    }

    slot.classList.add("devlog-edit__attachment--replaced");
    const label = slot.querySelector(".devlog-edit__attachment-replace-label");
    if (label) label.textContent = "Replaced";
  }
}
