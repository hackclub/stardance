import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "input",
    "item",
    "results",
    "dynamicJumpResults",
    "dynamicJumpList",
    "dynamicMissionResults",
    "dynamicMissionList",
  ];
  static values = { searchUrl: String, missionSearchUrl: String };

  connect() {
    this._activeIndex = -1;
    this._searchTimer = null;
    this._commandTimer = null;
    this._missionRequest = null;
    this._commandRequest = null;
    if (this.hasResultsTarget)
      this._initialResults = this.resultsTarget.innerHTML;
    this._boundGlobalKey = this._globalKey.bind(this);
    document.addEventListener("keydown", this._boundGlobalKey);
  }

  disconnect() {
    document.removeEventListener("keydown", this._boundGlobalKey);
    clearTimeout(this._searchTimer);
    clearTimeout(this._commandTimer);
    this._cancelRequests();
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
    clearTimeout(this._searchTimer);
    clearTimeout(this._commandTimer);
    this._cancelRequests();
    this._clearDynamicJump();
    this._clearDynamicMissions();
    if (this.hasResultsTarget && this.hasSearchUrlValue) {
      this._restoreInitialResults();
    } else {
      this.filter();
    }
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
    clearTimeout(this._commandTimer);
    this._cancelRequests();

    const directRoutes = [
      {
        pattern: /^user#(\d+)$/i,
        path: (id) => `/admin/users/${id}`,
        label: "User",
      },
      {
        pattern: /^audit#(\d+)$/i,
        path: (id) => `/admin/audit_logs/${id}`,
        label: "Audit Log",
      },
      {
        pattern: /^project#(\d+)$/i,
        path: (id) => `/admin/projects/${id}`,
        label: "Project",
      },
      {
        pattern: /^report#(\d+)$/i,
        path: (id) => `/admin/reports/${id}`,
        label: "Report",
      },
      {
        pattern: /^order#(\d+)$/i,
        path: (id) => `/admin/shop/orders/${id}`,
        label: "Shop Order",
      },
    ];
    const directMatch = directRoutes.reduce(
      (found, r) =>
        found ||
        (query.match(r.pattern) && { id: query.match(r.pattern)[1], ...r }),
      null,
    );
    if (directMatch) {
      this._clearDynamicMissions();
      this._renderDynamicJump({
        label: `${directMatch.label} #${directMatch.id}`,
        path: directMatch.path(directMatch.id),
      });
      return;
    }
    this._clearDynamicJump();

    if (query.length >= 2 && this.hasMissionSearchUrlValue) {
      this._searchTimer = setTimeout(() => this._fetchAll(query), 200);
    } else {
      this._clearDynamicMissions();
    }

    if (this.hasResultsTarget && this.hasSearchUrlValue) {
      if (query.length > 0) {
        this.resultsTarget.innerHTML =
          '<p class="command-palette__empty">Searching...</p>';
        this._commandTimer = setTimeout(() => this._loadResults(query), 180);
      } else {
        this._restoreInitialResults();
      }
      return;
    }

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
        this._activate(event.shiftKey);
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
    const { path, focus, method, adminPath } = item.dataset;
    const useAdminPath = event.shiftKey && adminPath;
    const effectivePath = useAdminPath ? adminPath : path;
    if (!effectivePath && !focus) return;

    this.close();
    if (focus && !useAdminPath) {
      document.querySelector(focus)?.focus();
    } else if (method === "post" && !useAdminPath) {
      this._postAction(effectivePath);
    } else {
      window.Turbo.visit(effectivePath);
    }
  }

  _fetchAll(query) {
    const q = encodeURIComponent(query);
    const request = new AbortController();
    this._missionRequest = request;

    fetch(`${this.missionSearchUrlValue}?q=${q}`, {
      headers: { Accept: "application/json" },
      signal: request.signal,
    })
      .then((r) => r.json())
      .then((missions) => {
        if (this._missionRequest === request)
          this._renderDynamicMissions(missions);
      })
      .catch(() => {
        if (this._missionRequest === request) this._clearDynamicMissions();
      })
      .finally(() => {
        if (this._missionRequest === request) this._missionRequest = null;
      });
  }

  _renderDynamicJump({ label, path }) {
    const list = this.dynamicJumpListTarget;
    list.innerHTML = "";
    const li = document.createElement("li");
    li.className = "command-palette__item";
    li.role = "option";
    li.id = "cp-dyn-jump";
    li.dataset.commandPaletteTarget = "item";
    li.dataset.action =
      "click->command-palette#select mouseenter->command-palette#highlight";
    li.dataset.path = path;
    li.innerHTML = `<span class="command-palette__item-title">${this._escape(label)}</span>`;
    list.appendChild(li);
    this.dynamicJumpResultsTarget.style.display = "";
  }

  _clearDynamicJump() {
    if (this.hasDynamicJumpListTarget)
      this.dynamicJumpListTarget.innerHTML = "";
    if (this.hasDynamicJumpResultsTarget)
      this.dynamicJumpResultsTarget.style.display = "none";
  }

  _renderDynamicMissions(missions) {
    const list = this.dynamicMissionListTarget;
    list.innerHTML = "";

    if (!missions.length) {
      this.dynamicMissionResultsTarget.style.display = "none";
      return;
    }

    missions.forEach((mission, i) => {
      const li = document.createElement("li");
      li.className = "command-palette__item";
      li.role = "option";
      li.id = `cp-dyn-mission-${i}`;
      li.dataset.commandPaletteTarget = "item";
      li.dataset.action =
        "click->command-palette#select mouseenter->command-palette#highlight";
      li.dataset.path = `/missions/${mission.slug}`;
      li.innerHTML = `<span class="command-palette__item-title">${this._escape(mission.name)}</span>`;
      list.appendChild(li);
    });

    this.dynamicMissionResultsTarget.style.display = "";
  }

  _clearDynamicMissions() {
    if (this.hasDynamicMissionListTarget)
      this.dynamicMissionListTarget.innerHTML = "";
    if (this.hasDynamicMissionResultsTarget)
      this.dynamicMissionResultsTarget.style.display = "none";
  }

  _escape(str) {
    return str
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
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

  _activate(shiftKey = false) {
    const item = this.itemTargets[this._activeIndex];
    const { path, focus, method, adminPath } = item?.dataset ?? {};
    const useAdminPath = shiftKey && adminPath;
    const effectivePath = useAdminPath ? adminPath : path;
    if (!effectivePath && !focus) return;

    this.close();
    if (focus && !useAdminPath) {
      document.querySelector(focus)?.focus();
    } else if (method === "post" && !useAdminPath) {
      this._postAction(effectivePath);
    } else {
      window.Turbo.visit(effectivePath);
    }
  }

  _loadResults(query) {
    const url = new URL(this.searchUrlValue, window.location.origin);
    url.searchParams.set("q", query);
    url.searchParams.set("surface", "command_palette");
    url.searchParams.set("current_path", window.location.pathname);
    const request = new AbortController();
    this._commandRequest = request;

    fetch(url.toString(), {
      headers: { Accept: "application/json" },
      signal: request.signal,
    })
      .then((r) => r.json())
      .then((data) => {
        if (this._commandRequest === request) this._renderResults(data);
      })
      .catch(() => {})
      .finally(() => {
        if (this._commandRequest === request) this._commandRequest = null;
      });
  }

  _renderResults(data) {
    const groups = [
      ["Commands", data.commands ?? []],
      ["Shop Orders", data.shop_orders ?? []],
      ["Projects", data.projects ?? []],
      ["Posts", data.posts ?? []],
      ["Users", data.users ?? []],
    ].filter(([, items]) => items.length > 0);

    if (!groups.length) {
      this.resultsTarget.innerHTML =
        '<p class="command-palette__empty">No results found.</p>';
      this._activeIndex = -1;
      this._clearActive();
      return;
    }

    let html = "";
    let idx = 0;
    groups.forEach(([label, items]) => {
      html += `<p class="command-palette__section-label">${this._escape(label)}</p><ul class="command-palette__list">`;
      items.forEach((item) => {
        const path = item.path ? `data-path="${this._escape(item.path)}"` : "";
        const focus = item.focus
          ? `data-focus="${this._escape(item.focus)}"`
          : "";
        const adminPath = item.admin_path
          ? `data-admin-path="${this._escape(item.admin_path)}"`
          : "";
        const method = item.method === "post" ? 'data-method="post"' : "";
        html += `<li class="command-palette__item" role="option" id="cp-sr-${idx++}"
                    data-command-palette-target="item"
                    data-action="click->command-palette#select mouseenter->command-palette#highlight"
                    ${path} ${focus} ${adminPath} ${method}>
                   <span class="command-palette__item-title">${this._escape(item.title ?? "")}</span>
                   ${item.subtitle ? `<span class="command-palette__item-meta">${this._escape(item.subtitle)}</span>` : ""}
                 </li>`;
      });
      html += "</ul>";
    });

    this.resultsTarget.innerHTML = html;
    this._activeIndex = -1;
    this._clearActive();
  }

  _restoreInitialResults() {
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

  _cancelRequests() {
    this._missionRequest?.abort();
    this._commandRequest?.abort();
    this._missionRequest = null;
    this._commandRequest = null;
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
