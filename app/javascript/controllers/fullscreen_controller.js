import { Controller } from "@hotwired/stimulus";

// Toggles the controller's element in and out of fullscreen. The button
// hides itself where the Fullscreen API is missing (e.g. iPhone Safari).
export default class extends Controller {
  static targets = ["button"];

  connect() {
    if (!document.fullscreenEnabled) this.buttonTarget.hidden = true;
  }

  toggle() {
    if (document.fullscreenElement) document.exitFullscreen();
    else this.element.requestFullscreen();
  }
}
