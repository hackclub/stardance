import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "item", "empty", "sentinel", "search"];
  static values = { pageSize: { type: Number, default: 6 } };

  connect() {
    this.visible = this.pageSizeValue;
    this.render();

    if (this.hasSentinelTarget) {
      this.observer = new IntersectionObserver(
        (entries) => entries.some((e) => e.isIntersecting) && this.showMore(),
        { rootMargin: "200px" },
      );
      this.observer.observe(this.sentinelTarget);
    }
  }

  disconnect() {
    this.observer?.disconnect();
  }

  filter() {
    this.visible = this.pageSizeValue; // a new query restarts from the top
    this.render();
  }

  showMore() {
    if (this.visible >= this.matches.length) return;

    this.visible += this.pageSizeValue;
    this.render();

    if (
      this.hasSentinelTarget &&
      !this.sentinelTarget.hidden &&
      this.sentinelTarget.getBoundingClientRect().top < window.innerHeight
    ) {
      this.showMore();
    }
  }

  guardToggle(event) {
    if (!this.hasSearchTarget || !this.searchTarget.contains(event.target))
      return;

    if (event.type === "click") {
      event.preventDefault();
    } else {
      event.stopPropagation();
    }
  }

  get matches() {
    const query = this.hasInputTarget
      ? this.inputTarget.value.trim().toLowerCase()
      : "";
    return this.itemTargets.filter(
      (item) => !query || item.dataset.searchText.includes(query),
    );
  }

  render() {
    const matches = this.matches;
    const shown = new Set(matches.slice(0, this.visible));
    this.itemTargets.forEach((item) => {
      item.hidden = !shown.has(item);
    });

    if (this.hasEmptyTarget) this.emptyTarget.hidden = matches.length > 0;
    if (this.hasSentinelTarget) {
      this.sentinelTarget.hidden = this.visible >= matches.length;
    }
  }
}
