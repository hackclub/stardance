import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "dropZone",
    "grid",
    "fileInput",
    "footer",
    "timeFrame",
    "warn",
    "form",
    "textarea",
    "submit",
    "attachWrap",
    "recordBtn",
  ];
  static values = {
    maxFiles: { type: Number, default: 4 },
    previewTimeUrl: String,
    hackatimeLinked: { type: Boolean, default: false },
    simpleMode: { type: Boolean, default: false },
  };

  #files = [];
  #urls = [];
  #composerOpen = false;
  #previewSeconds = 0;

  #onTimeFrameLoad = (event) => {
    if (!this.hasTimeFrameTarget || event.target !== this.timeFrameTarget)
      return;
    const hint = this.timeFrameTarget.querySelector("[data-seconds]");
    this.#previewSeconds = hint ? parseInt(hint.dataset.seconds || "0", 10) : 0;
    this.#updateSubmit();
  };

  connect() {
    if (this.hasFileInputTarget) {
      this.#acceptedTypes = this.fileInputTarget.accept
        .split(",")
        .map((t) => t.trim());
    }
    this.element.addEventListener("turbo:frame-load", this.#onTimeFrameLoad);
    // Auto-open composer in simple mode (e.g. ship modal)
    if (this.simpleModeValue) {
      this.#composerOpen = true;
    }
    this.#resizeTextarea();
    this.#updateSubmit();
    this.#loadPreviewTime();
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this.#onTimeFrameLoad);
    this.#revokeUrls();
  }

  autogrow() {
    this.#resizeTextarea();
  }

  refreshSubmit() {
    this.#updateSubmit();
  }

  collapseIfEmpty() {
    setTimeout(() => {
      if (this.element.contains(document.activeElement)) return;
      const hasBody =
        this.hasTextareaTarget && this.textareaTarget.value.trim().length > 0;
      const hasFiles = this.#files.length > 0;
      if (!hasBody && !hasFiles) {
        this.#composerOpen = false;
        this.#updateSubmit();
      }
    }, 150);
  }

  #updateSubmit() {
    let enabled;
    if (this.simpleModeValue) {
      enabled =
        this.hasTextareaTarget && this.textareaTarget.value.trim().length > 0;
    } else {
      enabled = this.#files.length > 0 && this.#previewSeconds >= 15 * 60;
    }
    if (this.hasAttachWrapTarget) {
      const show = this.#composerOpen && this.#files.length === 0;
      this.attachWrapTarget.classList.toggle(
        "feed-composer__attach-wrap--expanded",
        show,
      );
    }
    if (this.hasSubmitTarget) {
      // Toggle whichever button-component's disabled-modifier the target
      // happens to use. Harmless if the class isn't present.
      this.submitTarget.classList.toggle("action-btn--disabled", !enabled);
      this.submitTarget.classList.toggle(
        "special-action-btn--disabled",
        !enabled,
      );
      if (this.simpleModeValue) {
        // Ship composer: plain native disable, no tooltip.
        this.submitTarget.disabled = !enabled;
      } else {
        // Devlog composer: soft-disable via aria-disabled rather than the
        // native attribute so the button still receives hover/focus and can
        // surface a tooltip explaining what's missing. guardSubmit() blocks
        // the actual submission.
        this.submitTarget.setAttribute("aria-disabled", String(!enabled));
        this.#setTooltip(enabled ? null : this.#disabledReason());
      }
    }
  }

  guardSubmit(event) {
    if (
      this.hasSubmitTarget &&
      this.submitTarget.getAttribute("aria-disabled") === "true"
    ) {
      event.preventDefault();
      return;
    }

    // Manually swap the button text and disable it to give feedback and
    // prevent double-clicks.
    if (this.hasSubmitTarget) {
      const label = this.submitTarget.querySelector(".action-btn__label");
      if (label) label.textContent = "Posting...";
      this.submitTarget.disabled = true;
    }
  }

  // Human-readable explanation of why the Post button is currently disabled,
  // listing every unmet requirement. Returns "" when nothing is missing.
  // Only the devlog composer (non-simple mode) surfaces this.
  #disabledReason() {
    const missing = [];
    if (this.#files.length === 0) missing.push("attach a screenshot or video");
    if (!this.hackatimeLinkedValue) {
      missing.push("link a Hackatime project to track your time");
    } else if (this.#previewSeconds < 15 * 60) {
      missing.push("log at least 15 minutes of coding time");
    }

    if (missing.length === 0) return "";
    return `To post, ${missing.join(" and ")}.`;
  }

  // Drive the tooltip controller on the submit button: set its message when
  // there's a reason to show one, and detach it entirely (by removing it from
  // data-controller) once the button is enabled so it stops popping.
  #setTooltip(message) {
    if (!this.hasSubmitTarget) return;
    const el = this.submitTarget;
    const controllers = (el.getAttribute("data-controller") || "")
      .split(/\s+/)
      .filter(Boolean);
    const hasTooltip = controllers.includes("tooltip");

    if (message) {
      el.dataset.tooltipMessageValue = message;
      if (!hasTooltip) {
        controllers.push("tooltip");
        el.setAttribute("data-controller", controllers.join(" "));
      }
    } else if (hasTooltip) {
      el.setAttribute(
        "data-controller",
        controllers.filter((c) => c !== "tooltip").join(" "),
      );
    }
  }

  #resizeTextarea() {
    if (!this.hasTextareaTarget) return;
    const el = this.textareaTarget;
    el.style.height = "auto";
    // scrollHeight is 0 when the element is inside a hidden dialog (display:none).
    // In that case leave height as "auto" so the rows attribute dictates the size
    // once the dialog opens, rather than locking it to 0px.
    if (el.scrollHeight > 0) {
      el.style.height = `${el.scrollHeight}px`;
    }
  }

  showInfo() {
    this.#composerOpen = true;
    if (this.hasFooterTarget) this.footerTarget.hidden = false;
    this.#updateSubmit();
    this.#loadPreviewTime();
  }

  selectProject(event) {
    event.preventDefault();
    const {
      postUrl,
      previewUrl,
      editUrl,
      hackatimeLinked,
      hardware,
      recordUrl,
    } = event.params;
    const linked = !!hackatimeLinked;
    const chip = event.currentTarget;

    chip.parentElement
      .querySelectorAll(".feed-composer__chip--active")
      .forEach((el) => {
        el.classList.remove("feed-composer__chip--active");
        el.removeAttribute("aria-current");
      });
    chip.classList.add("feed-composer__chip--active");
    chip.setAttribute("aria-current", "true");

    if (this.hasFormTarget) {
      this.formTarget.action = postUrl;
      const csrfToken = document.querySelector(
        "meta[name='csrf-token']",
      )?.content;
      const tokenField = this.formTarget.querySelector(
        "input[name='authenticity_token']",
      );
      if (csrfToken && tokenField) tokenField.value = csrfToken;
    }
    this.previewTimeUrlValue = previewUrl;
    this.hackatimeLinkedValue = linked;

    this.#previewSeconds = 0;
    if (this.hasTimeFrameTarget) {
      this.timeFrameTarget.hidden = !linked;
      this.timeFrameTarget.removeAttribute("src");
      this.timeFrameTarget.innerHTML =
        '<span class="feed-composer__info-text">Loading time...</span>';
    }
    if (this.hasWarnTarget) {
      this.warnTarget.hidden = linked;
      if (editUrl) this.warnTarget.href = editUrl;
    }

    // The Record button (home composer only) applies to hardware projects; show
    // it and point it at the newly-selected project's create-session endpoint.
    if (this.hasRecordBtnTarget) {
      this.recordBtnTarget.hidden = !hardware;
      if (recordUrl) {
        this.recordBtnTarget.dataset.lookoutRecorderCreateUrlValue = recordUrl;
      }
    }

    if (this.#composerOpen) this.#loadPreviewTime();
    this.#updateSubmit();
  }

  #loadPreviewTime() {
    if (!this.hasTimeFrameTarget || this.timeFrameTarget.hidden) return;
    if (!this.hasPreviewTimeUrlValue) return;
    if (this.timeFrameTarget.getAttribute("src")) return;
    this.timeFrameTarget.setAttribute("src", this.previewTimeUrlValue);
  }

  selectFiles() {
    this.#addFiles(this.fileInputTarget.files);
  }

  drop(event) {
    event.preventDefault();
    this.dropZoneTarget.classList.remove("feed-composer--dragover");
    this.#addFiles(event.dataTransfer.files);
  }

  dragover(event) {
    event.preventDefault();
    this.dropZoneTarget.classList.add("feed-composer--dragover");
  }

  dragleave() {
    this.dropZoneTarget.classList.remove("feed-composer--dragover");
  }

  paste(event) {
    const files = Array.from(event.clipboardData?.files || []);
    if (files.length === 0) return;
    event.preventDefault();
    this.#addFiles(files);
  }

  removeFile({ params: { index } }) {
    this.#files.splice(index, 1);
    this.#render();
  }

  // private

  #acceptedTypes = [];

  #addFiles(fileList) {
    const incoming = Array.from(fileList).filter((f) =>
      this.#acceptedTypes.includes(f.type),
    );
    const room = this.maxFilesValue - this.#files.length;
    this.#files.push(...incoming.slice(0, Math.max(0, room)));
    this.#render();
  }

  #render() {
    this.#revokeUrls();
    this.gridTarget.innerHTML = "";

    if (this.#files.length === 0) {
      this.gridTarget.hidden = true;
      this.gridTarget.dataset.count = "0";
      this.#syncInput();
      this.#updateSubmit();
      return;
    }

    this.gridTarget.hidden = false;
    this.gridTarget.dataset.count = String(this.#files.length);

    this.#files.forEach((file, i) => {
      const wrap = document.createElement("div");
      wrap.className = "feed-composer__preview";

      if (file.type.startsWith("image/")) {
        const url = URL.createObjectURL(file);
        this.#urls.push(url);
        const img = document.createElement("img");
        img.src = url;
        img.alt = file.name;
        img.className = "feed-composer__preview-image";
        wrap.appendChild(img);
      } else {
        const vid = document.createElement("video");
        vid.src = URL.createObjectURL(file);
        this.#urls.push(vid.src);
        vid.preload = "metadata";
        vid.muted = true;
        vid.className = "feed-composer__preview-video";
        vid.addEventListener(
          "loadeddata",
          () => {
            vid.currentTime = 0.1;
          },
          { once: true },
        );
        wrap.appendChild(vid);
      }

      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "feed-composer__preview-remove";
      btn.setAttribute("aria-label", "Remove attachment");
      btn.dataset.action = "composer#removeFile";
      btn.dataset.composerIndexParam = String(i);
      btn.innerHTML = `<svg aria-hidden="true" viewBox="0 0 320.591 320.591" xmlns="http://www.w3.org/2000/svg"><path d="m30.391 318.583c-7.86.457-15.59-2.156-21.56-7.288-11.774-11.844-11.774-30.973 0-42.817l257.812-257.813c12.246-11.459 31.462-10.822 42.921 1.424 10.362 11.074 10.966 28.095 1.414 39.875l-259.331 259.331c-5.893 5.058-13.499 7.666-21.256 7.288z"/><path d="m287.9 318.583c-7.966-.034-15.601-3.196-21.257-8.806l-257.813-257.814c-10.908-12.738-9.425-31.908 3.313-42.817 11.369-9.736 28.136-9.736 39.504 0l259.331 257.813c12.243 11.462 12.876 30.679 1.414 42.922-.456.487-.927.958-1.414 1.414-6.35 5.522-14.707 8.161-23.078 7.288z"/></svg>`;
      wrap.appendChild(btn);

      this.gridTarget.appendChild(wrap);
    });

    this.#syncInput();
    this.#updateSubmit();
  }

  #syncInput() {
    const dt = new DataTransfer();
    this.#files.forEach((f) => dt.items.add(f));
    this.fileInputTarget.files = dt.files;
  }

  #revokeUrls() {
    this.#urls.forEach((u) => URL.revokeObjectURL(u));
    this.#urls = [];
  }
}
