import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["template"];

  play() {
    if (document.querySelector("dialog.buku-x3-reveal")) return;

    const content = this.templateTarget.content.cloneNode(true);
    const dialog = content.querySelector("dialog");
    if (!dialog) return;

    // Give each preview a fresh animation timeline, even with a warm cache.
    const url = new URL(
      dialog.dataset.bukuX3RevealAnimationUrlValue,
      location.href,
    );
    url.searchParams.set("preview", Date.now());
    dialog.dataset.bukuX3RevealAnimationUrlValue = url.href;
    document.body.append(content);
  }
}
