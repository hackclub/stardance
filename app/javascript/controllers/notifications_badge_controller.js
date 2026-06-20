import { Controller } from "@hotwired/stimulus";
import consumer from "../channels/consumer";

// Subscribes to the per-user notifications channel and updates the sidebar
// badge in real time as the unseen count changes.
//
// Markup:
//   <a class="sidebar__nav-link" data-controller="notifications-badge">
//     <span data-notifications-badge-target="badge" class="sidebar__nav-badge" hidden>0</span>
//   </a>
export default class extends Controller {
  static targets = ["badge"];

  connect() {
    this.subscription = consumer.subscriptions.create("NotificationsChannel", {
      received: (data) => this.updateBadge(data.unread_count),
    });
  }

  disconnect() {
    this.subscription?.unsubscribe();
    this.subscription = null;
  }

  updateBadge(count) {
    if (!this.hasBadgeTarget) return;

    const safeCount = Number.isFinite(count)
      ? Math.max(0, Math.floor(count))
      : 0;
    this.badgeTarget.textContent = safeCount;
    this.badgeTarget.setAttribute("aria-label", `${safeCount} unread`);
    this.badgeTarget.hidden = safeCount === 0;
  }
}
