import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["slot", "preview", "removeFlag", "grid", "addSlotTemplate"];
  static values = { maxAttachments: Number };

  replacePreview({ target }) {
    const slot = target.closest("[data-devlog-edit-target='slot']");
    const preview = slot.querySelector("[data-devlog-edit-target='preview']");
    const removeFlag = slot.querySelector(
      "[data-devlog-edit-target='removeFlag']",
    );
    const file = target.files[0];
    if (!file) return;

    // Add slots have nothing to remove; filling one offers another.
    if (removeFlag) {
      removeFlag.disabled = false;
    } else if (!slot.dataset.filled) {
      slot.dataset.filled = "true";
      this.#appendAddSlot();
    }

    const url = URL.createObjectURL(file);
    if (file.type.startsWith("video/")) {
      preview.innerHTML = `<video src="${url}" controls class="devlog-edit__attachment-media"></video>`;
    } else {
      preview.innerHTML = `<img src="${url}" alt="" class="devlog-edit__attachment-media">`;
    }

    slot.classList.add("devlog-edit__attachment--replaced");
    const label = slot.querySelector(".devlog-edit__attachment-replace-label");
    if (label) label.textContent = removeFlag ? "Replaced" : "Added";
  }

  #appendAddSlot() {
    if (this.slotTargets.length >= this.maxAttachmentsValue) return;

    this.gridTarget.append(this.addSlotTemplateTarget.content.cloneNode(true));
  }
}
