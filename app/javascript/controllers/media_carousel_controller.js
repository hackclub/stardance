import { Controller } from "@hotwired/stimulus";

// Horizontal scroll-snap carousel with dot indicators and edge-aware arrows.
// Styling hooks come in via Stimulus classes so any block (feed media, shop
// galleries, ...) can reuse it with its own BEM names.
export default class extends Controller {
  static targets = ["viewport", "dot", "prevArrow", "nextArrow"];
  static classes = ["dotActive", "arrowHidden"];

  connect() {
    this.activeIndex = 0;
    this.observer = new IntersectionObserver(
      (entries) => {
        // A swipe delivers the leaving and entering slides in one batch, both
        // with isIntersecting true; only the most-visible one is the active
        // slide.
        const best = entries.reduce((a, b) =>
          b.intersectionRatio > a.intersectionRatio ? b : a,
        );
        if (best.intersectionRatio < 0.5) return;
        const index = [...this.viewportTarget.children].indexOf(best.target);
        if (index >= 0) this.setActive(index);
      },
      { root: this.viewportTarget, threshold: 0.5 },
    );

    [...this.viewportTarget.children].forEach((slide) =>
      this.observer.observe(slide),
    );
  }

  disconnect() {
    this.observer?.disconnect();
  }

  prev() {
    this.scrollToIndex(this.activeIndex - 1);
  }

  next() {
    this.scrollToIndex(this.activeIndex + 1);
  }

  goTo(event) {
    this.scrollToIndex(parseInt(event.currentTarget.dataset.index, 10));
  }

  // Scroll only the viewport; scrollIntoView would also scroll ancestors
  // (the page or the post panel) to reveal a partially visible card.
  scrollToIndex(index) {
    if (!this.viewportTarget.children[index]) return;
    this.viewportTarget.scrollTo({
      left: index * this.viewportTarget.clientWidth,
      behavior: "smooth",
    });
  }

  setActive(index) {
    this.activeIndex = index;
    this.updateDots(index);
    this.updateArrows(index);
  }

  updateDots(activeIndex) {
    if (!this.hasDotActiveClass) return;
    this.dotTargets.forEach((dot, i) => {
      dot.classList.toggle(this.dotActiveClass, i === activeIndex);
    });
  }

  updateArrows(activeIndex) {
    if (!this.hasArrowHiddenClass) return;
    const lastIndex = this.viewportTarget.children.length - 1;
    if (this.hasPrevArrowTarget) {
      this.prevArrowTarget.classList.toggle(
        this.arrowHiddenClass,
        activeIndex === 0,
      );
    }
    if (this.hasNextArrowTarget) {
      this.nextArrowTarget.classList.toggle(
        this.arrowHiddenClass,
        activeIndex === lastIndex,
      );
    }
  }
}
