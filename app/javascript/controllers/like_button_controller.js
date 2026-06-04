import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["btn", "count", "sprite"];
  static values = { url: String, liked: Boolean };

  toggle(event) {
    event.preventDefault();

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
    const method = this.likedValue ? "DELETE" : "POST";
    const nowLiked = !this.likedValue;

    if (nowLiked) {
      this.spriteTarget.classList.remove("is-liked", "is-animating");
      requestAnimationFrame(() => {
        this.spriteTarget.classList.add("is-animating");
        setTimeout(() => {
          this.spriteTarget.classList.remove("is-animating");
          this.spriteTarget.classList.add("is-liked");
        }, 1000);
      });
    } else {
      this.spriteTarget.classList.remove("is-liked", "is-animating");
    }

    fetch(this.urlValue, {
      method,
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": csrf,
      },
    })
      .then((res) => res.json())
      .then(({ liked, likes_count }) => {
        this.likedValue = liked;
        this.countTarget.textContent = likes_count;
        this.btnTarget.classList.toggle("like-button__btn--liked", liked);
      });
  }
}
