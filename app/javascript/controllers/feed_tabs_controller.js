import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["tab"];
  static values = { feedUrl: String };

  switch(event) {
    event.preventDefault();
    const tab = event.currentTarget.dataset.tab;

    this.tabTargets.forEach((el) => {
      el.classList.toggle("feed-tabs__tab--active", el.dataset.tab === tab);
    });

    const url = new URL(this.feedUrlValue, window.location.origin);
    if (tab !== "for_you") {
      url.searchParams.set("tab", tab);
    }

    const frame = document.querySelector("turbo-frame#home_feed");
    if (!frame) return;

    frame.innerHTML =
      '<div class="feed-loading" role="status" aria-live="polite">' +
      '<span class="feed-loading__spinner" aria-hidden="true"></span>' +
      '<span class="feed-loading__label">Loading the feed&hellip;</span>' +
      "</div>";

    frame.src = url.toString();
  }
}
