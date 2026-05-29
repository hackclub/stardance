import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["modal", "content", "image", "video"];

  connect() {
    this.closeOnOutsideClick = this.closeOnOutsideClick.bind(this);
    this.handleEscapeKey = this.handleEscapeKey.bind(this);
  }

  open(event) {
    event.preventDefault();
    const link = event.currentTarget;
    const mediaUrl = link.href;
    const isVideo = link.classList.contains("video-item");

    if (isVideo) {
      // Show video
      this.videoTarget.src = mediaUrl;
      this.videoTarget.classList.remove("hidden");
      this.imageTarget.classList.add("hidden");
    } else {
      // Show image
      this.imageTarget.src = mediaUrl;
      this.imageTarget.classList.remove("hidden");
      this.videoTarget.classList.add("hidden");
      this.videoTarget.pause();
      this.videoTarget.src = "";
    }

    this.modalTarget.classList.add("is-open");

    // Add event listeners
    setTimeout(() => {
      document.addEventListener("click", this.closeOnOutsideClick);
      document.addEventListener("keydown", this.handleEscapeKey);
    }, 0);
  }

  close(event) {
    if (event) {
      event.preventDefault();
    }

    // Pause video if playing
    if (!this.videoTarget.classList.contains("hidden")) {
      this.videoTarget.pause();
      this.videoTarget.src = "";
    }

    this.modalTarget.classList.remove("is-open");
    document.removeEventListener("click", this.closeOnOutsideClick);
    document.removeEventListener("keydown", this.handleEscapeKey);
  }

  closeOnOutsideClick(event) {
    // Close if clicking outside the content
    if (event.target === this.modalTarget) {
      this.close();
    }
  }

  handleEscapeKey(event) {
    if (event.key === "Escape") {
      this.close();
    }
  }

  stopPropagation(event) {
    // Prevent clicks on content from closing modal
    event.stopPropagation();
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick);
    document.removeEventListener("keydown", this.handleEscapeKey);
  }
}
