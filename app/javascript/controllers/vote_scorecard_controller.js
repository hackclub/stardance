import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["counter", "submit"];
  static values = {
    requiredScoreCount: Number,
    minimumWordCount: Number,
  };

  connect() {
    this.validate();
  }

  validate() {
    const wordCount = this.feedbackWordCount;
    const valid =
      this.selectedScoreCount === this.requiredScoreCountValue &&
      wordCount >= this.minimumWordCountValue;

    this.submitTarget.disabled = !valid;
    this.submitTarget.classList.toggle("action-btn--disabled", !valid);
    this.counterTarget.textContent = `${wordCount}/${this.minimumWordCountValue} words`;
    this.counterTarget.classList.toggle(
      "vote-scorecard__word-count--complete",
      wordCount >= this.minimumWordCountValue,
    );
  }

  get selectedScoreCount() {
    return new Set(
      Array.from(
        this.element.querySelectorAll(".vote-score__input:checked"),
      ).map((input) => input.name),
    ).size;
  }

  get feedbackWordCount() {
    const feedback = this.element.querySelector(".vote-scorecard__textarea");
    return (feedback?.value.trim().split(/\s+/).filter(Boolean) || []).length;
  }
}
