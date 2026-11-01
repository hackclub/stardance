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

    // Hackatime project names are user-controlled (Hackatime accepts any
    // string), so build the tag from DOM nodes rather than an HTML string.
    const tag = document.createElement("span");
    tag.className = "project-show__hackatime-tag";
    tag.dataset.hackatimeId = id;
    tag.dataset.previouslyLinked = previouslyLinked.toString();

    const removeBtn = document.createElement("button");
    removeBtn.type = "button";
    removeBtn.className = "project-show__hackatime-tag-remove";
    removeBtn.dataset.action = "hackatime-link#remove";
    removeBtn.dataset.id = id;
    removeBtn.setAttribute("aria-label", `Remove ${name}`);
    removeBtn.textContent = "×";

    const input = document.createElement("input");
    input.type = "hidden";
    input.name = "project[hackatime_project_ids][]";
    input.value = id;

    tag.append(
      this.textSpan("project-show__hackatime-tag-name", name),
      this.textSpan("project-show__hackatime-tag-time", `${hours}h`),
      removeBtn,
      input,
    );

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
    btn.append(
      this.textSpan("project-show__hackatime-dropdown-name", name),
      this.textSpan("project-show__hackatime-dropdown-time", `${hours}h`),
    );

    this.dropdownTarget.appendChild(btn);
    tag.remove();
    this.placeholderTarget.hidden =
      this.tagsTarget.querySelectorAll(".project-show__hackatime-tag").length >
      0;
  }

  textSpan(className, text) {
    const span = document.createElement("span");
    span.className = className;
    span.textContent = text;
    return span;
  }
}
