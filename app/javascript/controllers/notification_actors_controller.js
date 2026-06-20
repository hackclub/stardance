import { Controller } from "@hotwired/stimulus";

// Expands an aggregated notification card downward to reveal every actor
// behind it (inline accordion, not a floating menu). The chevron button lives
// alongside the avatars; the list sits at the bottom of the card body.
//
// The whole card is the toggle: data-action="click->notification-actors#toggle"
// lives on the <li>, so clicking anywhere on an aggregated card expands it —
// except on a real link inside (those navigate).
//
// Markup (see Notifications::ItemComponent):
//   <li class="notifications-item" data-controller="notification-actors"
//       data-action="click->notification-actors#toggle">
//     <button data-notification-actors-target="toggle">▾</button>
//     <ul data-notification-actors-target="list" hidden>…actors…</ul>
//   </li>
export default class extends Controller {
  static targets = ["toggle", "list"];

  toggle(event) {
    // Let actual links (actor / project / the expanded list rows) navigate.
    if (event.target.closest("a")) return;
    if (!this.hasListTarget) return;
    event.preventDefault();

    const expanded = this.toggleTarget.getAttribute("aria-expanded") === "true";
    this.toggleTarget.setAttribute("aria-expanded", String(!expanded));
    this.listTarget.hidden = expanded;
  }
}
