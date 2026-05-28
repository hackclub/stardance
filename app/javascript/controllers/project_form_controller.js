import { Controller } from "@hotwired/stimulus";

// data-controller="project-form"
export default class extends Controller {
  static targets = [
    "title",
    "description",
    "demoUrl",
    "repoUrl",
    "readmeUrl",
    "readmeContainer",
    "submit",
    "requirementsContainer",
  ];

  // Maps form-field keys → the requirement keys they satisfy. Reachability
  // / format checks live downstream of presence — we hide them optimistically
  // when the user enters *anything* for the URL; if the server later rejects
  // them at save time, they'll re-render.
  static FIELD_REQUIREMENT_MAP = {
    description: ["description"],
    demo_url: ["demo_url", "demo_url_reachable"],
    repo_url: ["repo_url", "repo_url_format", "repo_cloneable"],
    readme_url: ["readme_url", "readme_url_reachable"],
    banner: ["banner"],
  };

  static values = {
    readmeLockedClass: {
      type: String,
      default: "project-form--readme-locked",
    },
  };

  connect() {
    this.submitting = false;
    this.userEditedReadme = false;
    this.debouncedDetect = this.debounce(() => this.detectReadme(), 120);
    this.boundRecheck = () => this.recheckRequirements();

    this.element.addEventListener("direct-upload:end", () => {
      this.submitting = false;
    });
    this.element.addEventListener("direct-upload:error", () => {
      this.submitting = false;
      if (this.hasSubmitTarget) this.submitTarget.disabled = false;
    });

    // Delegated listeners on the form so we catch every field, including
    // file inputs nested inside StarImageInputComponent.
    this.element.addEventListener("input", this.boundRecheck);
    this.element.addEventListener("change", this.boundRecheck);

    this.restoreReadmeState();
    this.recheckRequirements();

    if (
      this.hasRepoUrlTarget &&
      this.hasReadmeUrlTarget &&
      !this.readmeUrlTarget.value
    ) {
      setTimeout(() => this.detectReadme(), 0);
    }
  }

  disconnect() {
    this.element.removeEventListener("input", this.boundRecheck);
    this.element.removeEventListener("change", this.boundRecheck);
  }

  recheckRequirements() {
    if (!this.hasRequirementsContainerTarget) return;

    const filled = {
      description:
        this.hasDescriptionTarget && this.fieldFilled(this.descriptionTarget),
      demo_url: this.hasDemoUrlTarget && this.fieldFilled(this.demoUrlTarget),
      repo_url: this.hasRepoUrlTarget && this.fieldFilled(this.repoUrlTarget),
      readme_url:
        this.hasReadmeUrlTarget && this.fieldFilled(this.readmeUrlTarget),
      banner: this.bannerFilled(),
    };

    const satisfied = new Set();
    for (const [field, isFilled] of Object.entries(filled)) {
      if (!isFilled) continue;
      const reqs = this.constructor.FIELD_REQUIREMENT_MAP[field] || [];
      reqs.forEach((k) => satisfied.add(k));
    }

    let remaining = 0;
    this.requirementsContainerTarget
      .querySelectorAll("[data-req-key]")
      .forEach((li) => {
        const key = li.dataset.reqKey;
        const hide = satisfied.has(key);
        li.hidden = hide;
        if (!hide) remaining += 1;
      });

    this.requirementsContainerTarget.hidden = remaining === 0;

    if (this.hasSubmitTarget) {
      const wasDisabled = this.submitTarget.disabled;
      const shouldDisable = remaining > 0;
      if (wasDisabled !== shouldDisable) {
        this.submitTarget.disabled = shouldDisable;
        this.submitTarget.classList.toggle(
          "special-action-btn--disabled",
          shouldDisable,
        );
      }
    }
  }

  fieldFilled(target) {
    if (!target) return false;
    return (target.value || "").trim().length > 0;
  }

  bannerFilled() {
    const input = this.element.querySelector(
      'input[type="file"][name="project[banner]"]',
    );
    if (input && input.files && input.files.length > 0) return true;
    // If the project already has a banner attached (server-rendered) the
    // `banner` requirement was never in the list to begin with — recheck
    // still works either way.
    return false;
  }

  validateTitle(event) {
    if (!this.hasTitleTarget) return;

    const el = this.titleTarget;
    const value = (el.value || "").trim();
    let message = "";

    if (!value) {
      message = "Title is required";
    } else if (value.length > 120) {
      message = "Title must be 120 characters or fewer";
    }

    this.setValidity(el, message, event);
  }

  validateDescription(event) {
    if (!this.hasDescriptionTarget) return;

    const el = this.descriptionTarget;
    const value = el.value || "";
    const message =
      value.length > 1000 ? "Description must be 1000 characters or fewer" : "";

    this.setValidity(el, message, event);
  }

  validateUrl(event) {
    const el = event?.target || null;
    if (!el) return;

    const value = (el.value || "").trim();
    let message = "";

    if (value.length > 0) {
      try {
        const url = new URL(value);
        if (!["http:", "https:"].includes(url.protocol)) {
          message = "URL must start with http or https";
        } else if (value.length > 2048) {
          message = "URL is too long";
        }
      } catch {
        message = "Enter a valid URL";
      }
    }

    this.setValidity(el, message, event);
  }

  onRepoInput(event) {
    this.validateUrl(event);
    this.debouncedDetect();
  }

  onRepoBlur(event) {
    this.validateUrl(event);
    this.detectReadme();
  }

  // Paste is the common path for GitHub URLs — run the autodetect
  // immediately rather than waiting for the input-debounce so the README
  // field is filled before the user reaches for the submit button.
  onRepoPaste() {
    setTimeout(() => this.detectReadme(), 0);
  }

  onReadmeInput(event) {
    if (!this.hasReadmeUrlTarget) return;

    this.userEditedReadme = true;
    this.readmeUrlTarget.removeAttribute("data-autofilled");
    this.setReadmeLocked(false);
    this.validateUrl(event);
  }

  async onSubmit(event) {
    const form = this.element.closest("form") || this.element;

    if (this.submitting) {
      event.preventDefault();
      return;
    }

    // Repo filled but README empty? Give the autodetect one synchronous shot
    // before native validation pops "Please fill out this field" on README.
    // The user may have clicked submit before the debounced detect fired.
    const repoFilled =
      this.hasRepoUrlTarget && this.fieldFilled(this.repoUrlTarget);
    const readmeEmpty =
      this.hasReadmeUrlTarget && !this.fieldFilled(this.readmeUrlTarget);

    if (repoFilled && readmeEmpty && !this._submitDetectAttempted) {
      event.preventDefault();
      this._submitDetectAttempted = true;
      await this.detectReadme();
      // Re-fire submit so the flow continues with the README populated.
      form.requestSubmit?.();
      return;
    }

    if (!form.checkValidity()) {
      form.reportValidity();
      event.preventDefault();
      form
        .querySelectorAll("input:invalid, textarea:invalid, select:invalid")
        .forEach((field) => this.triggerShake(field));
      return;
    }

    this.submitting = true;
    if (this.hasSubmitTarget) this.submitTarget.disabled = true;
  }

  async detectReadme() {
    if (!this.hasRepoUrlTarget || !this.hasReadmeUrlTarget) return;
    if (this.userEditedReadme && !this.readmeUrlTarget.dataset.autofilled) {
      return;
    }

    const repoValue = (this.repoUrlTarget.value || "").trim();
    if (!repoValue) return;

    let url;
    try {
      url = new URL(repoValue);
    } catch {
      this.revealReadme();
      return;
    }

    const host = url.host.toLowerCase();
    const [, owner, rawRepo] = (url.pathname || "").split("/");
    if (!owner || !rawRepo) {
      this.revealReadme();
      return;
    }

    const repo = rawRepo.replace(/\.git$/i, "");
    let readmeUrl = null;

    try {
      if (host === "github.com") {
        readmeUrl = await this.findGithubReadme(owner, repo);
      } else if (host === "gitlab.com") {
        readmeUrl = await this.findGitlabReadme(owner, repo);
      } else {
        this.revealReadme();
        return;
      }
    } catch {
      this.revealReadme();
      return;
    }

    if (!readmeUrl) {
      this.revealReadme();
      return;
    }

    if (
      !this.readmeUrlTarget.value ||
      this.readmeUrlTarget.dataset.autofilled
    ) {
      this.readmeUrlTarget.value = readmeUrl;
      this.readmeUrlTarget.dataset.autofilled = "true";
      this.userEditedReadme = false;
      this.showReadme();
      this.setReadmeLocked(true);
      this.validateUrl({ target: this.readmeUrlTarget });
    }
  }

  async findGithubReadme(owner, repo) {
    const api = `https://api.github.com/repos/${owner}/${repo}/readme`;

    try {
      const res = await fetch(api, {
        headers: { Accept: "application/vnd.github.v3+json" },
        cache: "no-store",
      });
      if (res.ok) {
        const json = await res.json();
        if (json?.download_url) return json.download_url;
      }
    } catch {}

    return null;
  }

  async findGitlabReadme(owner, repo) {
    const project = encodeURIComponent(`${owner}/${repo}`);
    const api = `https://gitlab.com/api/v4/projects/${project}/repository/files/README.md?ref=HEAD`;

    try {
      const res = await fetch(api, { cache: "no-store" });
      if (res.ok) {
        return `https://gitlab.com/${owner}/${repo}/-/raw/HEAD/README.md`;
      }
    } catch {}

    return null;
  }

  revealReadme() {
    this.showReadme();
    this.setReadmeLocked(false);
  }

  restoreReadmeState() {
    if (!this.hasReadmeUrlTarget) return;

    const hasValue = (this.readmeUrlTarget.value || "").trim().length > 0;
    if (hasValue) this.showReadme();

    const autofilled = this.readmeUrlTarget.dataset.autofilled === "true";
    this.userEditedReadme = hasValue && !autofilled;
    this.setReadmeLocked(autofilled);
  }

  showReadme() {
    if (this.hasReadmeContainerTarget) {
      this.readmeContainerTarget.hidden = false;
    }
  }

  setReadmeLocked(locked) {
    if (!this.hasReadmeUrlTarget) return;

    this.readmeUrlTarget.readOnly = locked;
    if (locked) {
      this.readmeUrlTarget.title = "Autodetected from repository";
    } else {
      this.readmeUrlTarget.removeAttribute("title");
    }

    if (this.hasReadmeContainerTarget) {
      this.readmeContainerTarget.classList.toggle(
        this.readmeLockedClassValue,
        locked,
      );
    }
  }

  setValidity(el, message, event) {
    el.setCustomValidity(message);

    if (event?.type === "blur") {
      el.reportValidity();
      if (message) this.triggerShake(el);
    }
  }

  debounce(fn, wait) {
    let t;
    return (...args) => {
      clearTimeout(t);
      t = setTimeout(() => fn.apply(this, args), wait);
    };
  }

  triggerShake(field) {
    const wrapper = field.closest(
      ".project-show__field, .ship__field, .project-show__identity",
    );
    if (!wrapper) return;

    wrapper.classList.remove("project-form--shake");
    wrapper.offsetWidth;
    wrapper.classList.add("project-form--shake");
    setTimeout(() => wrapper.classList.remove("project-form--shake"), 400);
  }
}
