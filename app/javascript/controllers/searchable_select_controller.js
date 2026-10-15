import { Controller } from "@hotwired/stimulus";

const SEARCH_DEBOUNCE_MS = 200;

// Two modes:
//   - static (no search-url value): every option is rendered server-side and
//     `filter` shows/hides them client-side. Fine for short, fixed lists.
//   - remote (search-url value set): the dropdown starts empty and options are
//     built from a user-search JSON endpoint (/search/users) while the user
//     types. Use this whenever the list is unbounded — rendering every option
//     inline also renders every avatar, which is what made the audit log page
//     fire thousands of requests.
export default class extends Controller {
  static targets = ["input", "dropdown", "option", "hiddenField"];
  static values = { open: Boolean, searchUrl: String };

  connect() {
    this.openValue = false;
    this.onClickOutside = this.handleClickOutside.bind(this);
    document.addEventListener("click", this.onClickOutside);
  }

  disconnect() {
    document.removeEventListener("click", this.onClickOutside);
    clearTimeout(this.searchTimer);
    this.pendingSearch?.abort();
  }

  get remote() {
    return this.hasSearchUrlValue;
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close();
    }
  }

  toggle() {
    this.openValue = !this.openValue;
  }

  open() {
    this.openValue = true;
    this.inputTarget.focus();
    if (this.remote) this.fetchOptions();
  }

  close() {
    this.openValue = false;
  }

  openValueChanged() {
    if (this.openValue) {
      this.dropdownTarget.style.display = "block";
    } else {
      this.dropdownTarget.style.display = "none";
    }
  }

  filter() {
    if (this.remote) {
      clearTimeout(this.searchTimer);
      this.searchTimer = setTimeout(
        () => this.fetchOptions(),
        SEARCH_DEBOUNCE_MS,
      );
      return;
    }

    const query = this.inputTarget.value.toLowerCase();

    this.optionTargets.forEach((option) => {
      const searchText =
        option.dataset.searchText || option.textContent.toLowerCase();
      if (searchText.includes(query)) {
        option.style.display = "flex";
      } else {
        option.style.display = "none";
      }
    });
  }

  async fetchOptions() {
    const query = this.inputTarget.value.trim();
    if (this.loadedQuery === query) return;

    // A slow earlier response must not overwrite a newer query's options.
    this.pendingSearch?.abort();
    this.pendingSearch = new AbortController();

    const url = new URL(this.searchUrlValue, window.location.origin);
    url.searchParams.set("q", query);

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: this.pendingSearch.signal,
      });
      if (!response.ok) return;

      this._renderOptions(await response.json());
      this.loadedQuery = query;
    } catch (error) {
      // Aborted by a newer keystroke, or the request failed — leave the
      // previous options in place rather than blanking the dropdown.
    }
  }

  _renderOptions(users) {
    this.dropdownTarget.replaceChildren(
      this._buildOption({ label: "All", action: "clear" }),
      ...users.map((user) =>
        this._buildOption({
          value: String(user.id),
          label: user.display_name,
          action: "select",
          avatar: user.avatar,
          suffix: `#${user.id}`,
        }),
      ),
    );
  }

  // Built with textContent rather than an HTML string so display names cannot
  // inject markup.
  _buildOption({ value = "", label, action, avatar = null, suffix = null }) {
    const option = document.createElement("div");
    option.className = "searchable-select-option";
    option.dataset.searchableSelectTarget = "option";
    option.dataset.action = `click->searchable-select#${action}`;
    option.dataset.value = value;
    option.dataset.label = label;
    option.dataset.searchText = `${label} ${suffix ?? ""}`.trim().toLowerCase();

    if (avatar) {
      const image = document.createElement("img");
      image.className = "searchable-select-avatar";
      image.loading = "lazy";
      image.alt = "";
      image.src = avatar;
      option.append(image);
    }

    const name = document.createElement("span");
    name.textContent = label;
    option.append(name);

    if (suffix) {
      const muted = document.createElement("span");
      muted.className = "searchable-select-muted";
      muted.textContent = suffix;
      option.append(muted);
    }

    return option;
  }

  select(event) {
    const value = event.currentTarget.dataset.value;
    const label = event.currentTarget.dataset.label;

    this.hiddenFieldTarget.value = value;
    this.inputTarget.value = label;
    this.close();
  }

  selectAndSubmit(event) {
    const value = event.currentTarget.dataset.value;
    const label = event.currentTarget.dataset.label;

    this.hiddenFieldTarget.value = value;
    this.inputTarget.value = label;
    this.close();

    const form = this.element.querySelector("form");
    if (form) {
      form.submit();
    }
  }

  clear() {
    this.hiddenFieldTarget.value = "";
    this.inputTarget.value = "";

    if (this.remote) {
      this.close();
      return;
    }

    this.filter();
  }
}
