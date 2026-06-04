import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "item", "results"];
  static values = { searchUrl: String };

  connect() {
    this._activeIndex = -1;
    this._searchTimer = null;
    this._initialResults = this.resultsTarget.innerHTML;
    this._boundGlobalKey = this._globalKey.bind(this);
    document.addEventListener("keydown", this._boundGlobalKey);
  }

  disconnect() {
    document.removeEventListener("keydown", this._boundGlobalKey);
    clearTimeout(this._searchTimer);
  }

  _globalKey(event) {
    const trigger = navigator.platform.toUpperCase().includes("MAC")
      ? event.metaKey
      : event.ctrlKey;
    if (trigger && event.key === "k") {
      event.preventDefault();
      this.element.showModal();
      this.inputTarget.select();
    }
  }

  close() {
    this.element.close();
    this.inputTarget.value = "";
    this._restoreInitialResults();
  }

  handleCancel(event) {
    event.preventDefault();
    this.close();
  }

  backdropClick(event) {
    const rect = this.element.getBoundingClientRect();
    const inside =
      event.clientX >= rect.left &&
      event.clientX <= rect.right &&
      event.clientY >= rect.top &&
      event.clientY <= rect.bottom;
    if (!inside) this.close();
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim();
    clearTimeout(this._searchTimer);

    if (query.length > 0 && this.hasSearchUrlValue) {
      this.resultsTarget.innerHTML =
        '<p class="command-palette__empty">Searching...</p>';
      this._searchTimer = setTimeout(() => this._loadResults(query), 180);
      return;
    }

    this._restoreInitialResults();

    const list = this.itemTargets[0]?.parentElement;
    if (!list) return;

    const scored = this.itemTargets.map((item) => {
      if (!query) return { item, score: 0, match: true };
      const title =
        item
          .querySelector(".command-palette__item-title")
          ?.textContent.toLowerCase() || "";
      const words = title.split(/\s+/);
      const keywords = (item.dataset.keywords || "").split(" ").filter(Boolean);

      let score = -1;
      if (title.startsWith(query)) score = 3;
      else if (words.some((w) => w.startsWith(query))) score = 2;
      else if (title.includes(query)) score = 1;
      else if (keywords.some((kw) => kw.startsWith(query))) score = 0;

      return { item, score, match: score >= 0 };
    });

    scored.sort((a, b) => b.score - a.score);
    scored.forEach(({ item, match }) => {
      item.style.display = match ? "" : "none";
      list.appendChild(item);
    });

    this._activeIndex = -1;
    this._clearActive();
  }

  handleKey(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this._move(1);
        break;
      case "ArrowUp":
        event.preventDefault();
        this._move(-1);
        break;
      case "Enter":
        event.preventDefault();
        this._activate();
        break;
      case "Escape":
        this.close();
        break;
    }
  }

  highlight(event) {
    const i = this.itemTargets.indexOf(event.currentTarget);
    if (i !== -1) {
      this._activeIndex = i;
      this._applyActive();
    }
  }

  select(event) {
    const item = event.currentTarget;
    this._visitItem(item);
  }

  resultsLoaded() {
    this._activeIndex = -1;
    this._clearActive();
  }

  _move(dir) {
    const visible = this.itemTargets.filter(
      (el) => el.style.display !== "none",
    );
    if (!visible.length) return;
    const currentItem = this.itemTargets[this._activeIndex];
    let visIdx = visible.indexOf(currentItem);
    visIdx = Math.max(0, Math.min(visible.length - 1, visIdx + dir));
    this._activeIndex = this.itemTargets.indexOf(visible[visIdx]);
    this._applyActive();
  }

  _activate() {
    const item = this.itemTargets[this._activeIndex];
    this._visitItem(item);
  }

  _visitItem(item) {
    if (!item?.dataset.path) return;

    this.close();
    if (item.dataset.method === "post") {
      this._postAction(item.dataset.path);
    } else {
      window.Turbo.visit(item.dataset.path);
    }
  }

  _loadResults(query) {
    const url = new URL(this.searchUrlValue, window.location.origin);
    url.searchParams.set("q", query);
    url.searchParams.set("surface", "command_palette");
    this.resultsTarget.src = url.toString();
  }

  _restoreInitialResults() {
    this.resultsTarget.removeAttribute("src");
    this.resultsTarget.innerHTML = this._initialResults;
    this._activeIndex = -1;
    this._clearActive();
  }

  _postAction(path) {
    const token = document.querySelector("meta[name='csrf-token']")?.content;
    const url = new URL(path, window.location.origin);
    const enable = url.searchParams.get("enable") === "true";
    fetch(path, {
      method: "POST",
      headers: { "X-CSRF-Token": token },
    }).then(() => {
      document.body.classList.toggle("streamer-mode", enable);
      const cb = document.getElementById("streamer_mode");
      if (cb) cb.checked = enable;
    });
  }

  _applyActive() {
    this._clearActive();
    const item = this.itemTargets[this._activeIndex];
    if (item) {
      item.classList.add("command-palette__item--active");
      item.scrollIntoView({ block: "nearest" });
      this.inputTarget.setAttribute("aria-activedescendant", item.id);
    }
  }

  _clearActive() {
    this.itemTargets.forEach((el) =>
      el.classList.remove("command-palette__item--active"),
    );
    if (this.hasInputTarget)
      this.inputTarget.setAttribute("aria-activedescendant", "");
  }
}
