import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["box", "tags", "dropdown", "addBtn", "placeholder"];
  static values = { hasExistingDevlogs: Boolean, items: Array };

  connect() {
    this.clickOutside = this.closeOnClickOutside.bind(this);
    document.addEventListener("click", this.clickOutside);
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutside);
  }

  toggle(event) {
    event.stopPropagation();
    this.dropdownTarget.hidden = !this.dropdownTarget.hidden;
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.hidden = true;
    }
  }

  select(event) {
    const btn = event.currentTarget;
    const id = btn.dataset.id;
    const name = btn.dataset.name;
    const hours = btn.dataset.hours;
    const previouslyLinked = btn.dataset.previouslyLinked === "true";

    if (
      this.hasExistingDevlogsValue &&
      !previouslyLinked &&
      !window.confirm(
        `Add "${name}"? It will be added to all existing devlogs and their logged time will be recalculated. Once saved, this Hackatime project cannot be removed.`,
      )
    ) {
      return;
    }

    const tag = document.createElement("span");
    tag.className = "project-show__hackatime-tag";
    tag.dataset.hackatimeId = id;
    tag.dataset.previouslyLinked = previouslyLinked.toString();
    tag.innerHTML = `
      <span class="project-show__hackatime-tag-name">${this.escapeHtml(name)}</span>
      <span class="project-show__hackatime-tag-time">${this.escapeHtml(hours)}h</span>
      <button type="button" class="project-show__hackatime-tag-remove" data-action="hackatime-link#remove" data-id="${id}" aria-label="Remove ${this.escapeHtml(name)}">&times;</button>
      <input type="hidden" name="project[hackatime_project_ids][]" value="${id}">
    `;

    this.tagsTarget.appendChild(tag);
    btn.remove();
    this.dropdownTarget.hidden = true;
    this.placeholderTarget.hidden = true;
  }

  remove(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    const tag = this.tagsTarget.querySelector(`[data-hackatime-id="${id}"]`);
    if (!tag) return;

    const name = tag.querySelector(
      ".project-show__hackatime-tag-name",
    ).textContent;
    const timeEl = tag.querySelector(".project-show__hackatime-tag-time");
    const hours = timeEl ? timeEl.textContent.replace("h", "") : "0";

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "project-show__hackatime-dropdown-item";
    btn.dataset.action = "hackatime-link#select";
    btn.dataset.id = id;
    btn.dataset.name = name;
    btn.dataset.hours = hours;
    btn.dataset.previouslyLinked = tag.dataset.previouslyLinked;
    btn.innerHTML = `
      <span class="project-show__hackatime-dropdown-name">${this.escapeHtml(name)}</span>
      <span class="project-show__hackatime-dropdown-time">${this.escapeHtml(hours)}h</span>
    `;

    this.dropdownTarget.appendChild(btn);
    tag.remove();
    this.placeholderTarget.hidden =
      this.tagsTarget.querySelectorAll(".project-show__hackatime-tag").length >
      0;
  }

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }
}
