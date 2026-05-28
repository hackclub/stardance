import { Controller } from "@hotwired/stimulus";

// Tabbed mission-guide flow. Sections are keyed on mission_step_id (shared
// across languages); completions persist remotely when a project is attached,
// otherwise to versioned localStorage.
export default class extends Controller {
  static targets = ["outlineItem", "progressBar", "completedCount"];
  static values = {
    sectionCount: Number,
    missionSlug: String,
    missionId: String,
    projectId: String,
    createUrl: String,
    completedStepIds: Array,
  };

  connect() {
    this.sections = Array.from(
      document.querySelectorAll("section.guide-section[data-mission-step-id]"),
    );

    this.completed = new Set(
      (this.completedStepIdsValue || []).map((id) => Number(id)),
    );
    if (!this.hasProjectIdValue || !this.projectIdValue) {
      this.hydrateFromLocalStorage();
    }

    if (this.sections.length === 0) {
      this.renderProgress();
      return;
    }

    this.injectPrevNext();
    this.bindOutlineClicks();
    this.bindHashChange();

    const initial = this.indexFromHash() ?? this.firstIncompleteIndex() ?? 0;
    this.activate(initial, { scroll: false, updateHash: false });
    this.renderProgress();
  }

  firstIncompleteIndex() {
    for (const section of this.sections) {
      const stepId = this.stepIdFor(section);
      if (stepId !== null && !this.completed.has(stepId)) {
        const idx = Number(section.dataset.sectionIndex);
        return Number.isNaN(idx) ? null : idx;
      }
    }
    return null;
  }

  disconnect() {
    if (this.onHashChange) {
      window.removeEventListener("hashchange", this.onHashChange);
    }
  }

  storageKey() {
    const slug = this.hasMissionSlugValue ? this.missionSlugValue : "_";
    return `stardance:v1:mission-progress:${slug}`;
  }

  hydrateFromLocalStorage() {
    try {
      const raw = window.localStorage.getItem(this.storageKey());
      if (!raw) return;
      const data = JSON.parse(raw);
      if (Array.isArray(data.stepIds)) {
        data.stepIds.forEach((id) => this.completed.add(Number(id)));
      }
    } catch {}
  }

  persistToLocalStorage() {
    try {
      window.localStorage.setItem(
        this.storageKey(),
        JSON.stringify({ stepIds: Array.from(this.completed) }),
      );
    } catch {}
  }

  bindOutlineClicks() {
    this.outlineItemTargets.forEach((item) => {
      const link = item.querySelector(".mission-guide__outline-link");
      if (!link) return;
      link.addEventListener("click", (e) => {
        e.preventDefault();
        const idx = Number(item.dataset.sectionIndex);
        if (!Number.isNaN(idx)) this.activate(idx);
      });
    });
  }

  bindHashChange() {
    this.onHashChange = () => {
      const idx = this.indexFromHash();
      if (idx !== null) this.activate(idx, { updateHash: false });
    };
    window.addEventListener("hashchange", this.onHashChange);
  }

  indexFromHash() {
    const hash = window.location.hash.replace(/^#/, "");
    if (!hash) return null;
    const section = this.sections.find((s) => s.id === hash);
    if (!section) return null;
    const idx = Number(section.dataset.sectionIndex);
    return Number.isNaN(idx) ? null : idx;
  }

  activate(index, { scroll = true, updateHash = true } = {}) {
    this.activeIndex = index;

    this.sections.forEach((section) => {
      const idx = Number(section.dataset.sectionIndex);
      section.classList.toggle("guide-section--hidden", idx !== index);
    });

    this.outlineItemTargets.forEach((item) => {
      const idx = Number(item.dataset.sectionIndex);
      item.classList.toggle("is-current", idx === index);
      const link = item.querySelector(".mission-guide__outline-link");
      if (link) {
        if (idx === index) {
          link.setAttribute("aria-current", "location");
        } else {
          link.removeAttribute("aria-current");
        }
      }
    });

    if (updateHash) {
      const activeSection = this.sections.find(
        (s) => Number(s.dataset.sectionIndex) === index,
      );
      if (activeSection) {
        history.replaceState(null, "", `#${activeSection.id}`);
      }
    }

    if (scroll) {
      this.element.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    this.renderProgress();
  }

  stepIdFor(section) {
    if (!section) return null;
    const raw = section.dataset.missionStepId;
    if (!raw) return null;
    const n = Number(raw);
    return Number.isNaN(n) ? null : n;
  }

  outlineStepIdFor(item) {
    if (!item) return null;
    const raw = item.dataset.missionStepId;
    if (!raw) return null;
    const n = Number(raw);
    return Number.isNaN(n) ? null : n;
  }

  renderProgress() {
    const total = this.hasSectionCountValue
      ? this.sectionCountValue
      : this.outlineItemTargets.length;

    let completedCount = 0;
    this.outlineItemTargets.forEach((item) => {
      const stepId = this.outlineStepIdFor(item);
      const isComplete = stepId !== null && this.completed.has(stepId);
      item.classList.toggle("is-completed", !!isComplete);
      const marker = item.querySelector(".mission-guide__outline-marker");
      if (marker) marker.textContent = isComplete ? "✓" : "○";
      if (isComplete) completedCount += 1;
    });

    if (this.hasProgressBarTarget) {
      this.progressBarTarget.value = completedCount;
      this.progressBarTarget.max = total;
    }
    if (this.hasCompletedCountTarget) {
      this.completedCountTarget.textContent = String(completedCount);
    }
  }

  // Optimistic completion toggle with rollback on server reject.
  setSectionState(stepId, desired) {
    const wasComplete = this.completed.has(stepId);
    if (wasComplete === desired) return;

    if (desired) this.completed.add(stepId);
    else this.completed.delete(stepId);
    this.renderProgress();

    if (
      this.hasProjectIdValue &&
      this.projectIdValue &&
      this.hasCreateUrlValue &&
      this.createUrlValue
    ) {
      this.persistRemote({ stepId, desired }).catch(() => {
        if (wasComplete) this.completed.add(stepId);
        else this.completed.delete(stepId);
        this.renderProgress();
      });
    } else {
      this.persistToLocalStorage();
    }
  }

  async persistRemote({ stepId, desired }) {
    const tokenEl = document.querySelector('meta[name="csrf-token"]');
    const token = tokenEl?.getAttribute("content") || "";

    const url = desired
      ? this.createUrlValue
      : `${this.createUrlValue.replace(/\/$/, "")}/${stepId}`;

    const init = {
      method: desired ? "POST" : "DELETE",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": token,
      },
    };
    if (desired) init.body = JSON.stringify({ mission_step_id: stepId });

    const response = await fetch(url, init);
    if (!response.ok) {
      throw new Error(`Server responded ${response.status}`);
    }
  }

  injectPrevNext() {
    this.sections.forEach((section) => {
      const idx = Number(section.dataset.sectionIndex);
      if (Number.isNaN(idx)) return;

      // Strip trailing HRs so they don't butt against the nav's border-top.
      const stripTrailingHrs = (root) => {
        let candidate = root.lastElementChild;
        while (candidate && candidate.tagName === "HR") {
          const prev = candidate.previousElementSibling;
          candidate.remove();
          candidate = prev;
        }
      };
      stripTrailingHrs(section);
      const wrapper = section.querySelector(":scope > .guide-content");
      if (wrapper) stripTrailingHrs(wrapper);

      const nav = document.createElement("nav");
      nav.className = "mission-guide__step-nav";
      nav.setAttribute("aria-label", "Section navigation");

      const prev = this.makeNavButton(idx - 1, "prev");
      const next = this.makeNavButton(idx + 1, "next");

      if (prev) {
        nav.appendChild(prev);
      } else {
        const spacer = document.createElement("span");
        spacer.className = "mission-guide__step-nav-spacer";
        nav.appendChild(spacer);
      }
      if (next) nav.appendChild(next);

      section.appendChild(nav);
    });
  }

  makeNavButton(targetIndex, direction) {
    const target = this.sections.find(
      (s) => Number(s.dataset.sectionIndex) === targetIndex,
    );
    if (!target) return null;
    const heading = target.querySelector("h2");
    const label = heading
      ? heading.textContent.trim()
      : `Section ${targetIndex + 1}`;

    const button = document.createElement("button");
    button.type = "button";
    button.className = `mission-guide__step-nav-button mission-guide__step-nav-button--${direction}`;
    button.dataset.targetIndex = String(targetIndex);

    const eyebrow = document.createElement("span");
    eyebrow.className = "mission-guide__step-nav-eyebrow";
    eyebrow.textContent = direction === "prev" ? "← Previous" : "Next →";

    const title = document.createElement("span");
    title.className = "mission-guide__step-nav-title";
    title.textContent = label;

    button.appendChild(eyebrow);
    button.appendChild(title);
    button.addEventListener("click", () => {
      if (direction === "next") {
        const current = this.sections.find(
          (s) => Number(s.dataset.sectionIndex) === this.activeIndex,
        );
        const currentStepId = current ? this.stepIdFor(current) : null;
        if (currentStepId !== null) this.setSectionState(currentStepId, true);
      } else {
        const destStepId = this.stepIdFor(target);
        if (destStepId !== null) this.setSectionState(destStepId, false);
      }
      this.activate(targetIndex);
    });

    return button;
  }
}
