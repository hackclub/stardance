import { Controller } from "@hotwired/stimulus";
import consumer from "../channels/consumer";

// Live-updates the inbox list as new notifications arrive. Receives the same
// NotificationsChannel broadcast as the badge controller; ignores messages
// that don't carry a `row_html` payload (count-only updates).
//
//   <main data-controller="notifications-inbox"
//         data-notifications-inbox-mark-seen-url-value="/my/notifications/mark_all_seen">
//     <ol data-notifications-inbox-target="list">
//       <li data-notification-id="…">…</li>
//     </ol>
//     <div data-notifications-inbox-target="empty">…</div>
//   </main>
const MARK_SEEN_DEBOUNCE_MS = 1500;

export default class extends Controller {
  static targets = ["list", "empty"];
  static values = { markSeenUrl: String };

  connect() {
    console.log("[notifications-inbox] connected");
    this.subscription = consumer.subscriptions.create("NotificationsChannel", {
      connected: () => console.log("[notifications-inbox] cable connected"),
      disconnected: () =>
        console.log("[notifications-inbox] cable disconnected"),
      rejected: () => console.warn("[notifications-inbox] cable rejected"),
      received: (data) => this.handleMessage(data),
    });
    this._markSeenTimer = null;
  }

  disconnect() {
    this.subscription?.unsubscribe();
    this.subscription = null;
    clearTimeout(this._markSeenTimer);
  }

  handleMessage(data) {
    console.log("[notifications-inbox] received", {
      hasRow: !!data.row_html,
      id: data.notification_id,
      aggregated: data.aggregated,
      unread: data.unread_count,
    });

    if (!data.row_html) {
      console.log("[notifications-inbox] ignoring count-only message");
      return;
    }
    if (!this.hasListTarget) {
      console.warn("[notifications-inbox] no list target on element");
      return;
    }

    try {
      const existing = this.listTarget.querySelector(
        `[data-notification-id="${data.notification_id}"]`,
      );

      if (existing) {
        console.log(
          "[notifications-inbox] replacing existing row",
          data.notification_id,
        );
        existing.outerHTML = data.row_html;
      } else {
        console.log(
          "[notifications-inbox] prepending new row",
          data.notification_id,
        );
        this.listTarget.insertAdjacentHTML("afterbegin", data.row_html);
        this.hideEmptyState();
      }

      this.scheduleMarkSeen();
    } catch (err) {
      console.error("[notifications-inbox] handler failed", err, data);
    }
  }

  hideEmptyState() {
    if (this.hasEmptyTarget) this.emptyTarget.hidden = true;
  }

  // Debounced POST to mark_all_seen — the user is looking at the inbox, so
  // any newly-arrived row counts as seen. Debounce so a burst of broadcasts
  // collapses into one request.
  scheduleMarkSeen() {
    if (!this.markSeenUrlValue) return;

    clearTimeout(this._markSeenTimer);
    this._markSeenTimer = setTimeout(
      () => this.markAllSeen(),
      MARK_SEEN_DEBOUNCE_MS,
    );
  }

  markAllSeen() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    if (!token) return;

    fetch(this.markSeenUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        Accept: "text/html",
      },
      credentials: "same-origin",
    }).catch((err) =>
      console.warn("[notifications-inbox] mark_all_seen failed", err),
    );
  }
}
