import { Controller } from "@hotwired/stimulus";

// Lightbox for the Sticky Streak stickers in the streak calendar. One dialog is
// shared by every day; the clicked day passes its image, name, description and
// (when the day is still unclaimed) the shop link that redeems it.
export default class extends Controller {
  static targets = ["dialog", "image", "name", "description", "claim"];

  open({ params }) {
    this.imageTarget.src = params.src;
    this.imageTarget.alt = params.name;
    this.nameTarget.textContent = params.name;

    this.descriptionTarget.textContent = params.description || "";
    this.descriptionTarget.hidden = !params.description;

    if (params.claimHref) {
      this.claimTarget.href = params.claimHref;
      this.claimTarget.hidden = false;
    } else {
      this.claimTarget.removeAttribute("href");
      this.claimTarget.hidden = true;
    }

    this.dialogTarget.showModal();
  }

  close() {
    this.dialogTarget.close();
  }
}
