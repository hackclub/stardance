import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["idea"];
  static values = { ideas: Array };

  shuffle() {
    const others = this.ideasValue.filter(
      (idea) => idea !== this.ideaTarget.textContent,
    );
    this.ideaTarget.textContent =
      others[Math.floor(Math.random() * others.length)];

    this.ideaTarget.classList.add("day-one-of-promo__idea-text--flip");
    this.ideaTarget.addEventListener(
      "animationend",
      () =>
        this.ideaTarget.classList.remove("day-one-of-promo__idea-text--flip"),
      { once: true },
    );
  }
}
