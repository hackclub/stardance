import {
  bindings,
  chordFromEvent,
  conflict,
  label,
  modified,
} from "./shortcut_bindings";

// Owns only the editor. Review actions remain in the keyboard controller.
export default class ShortcutSettings {
  constructor(controller) {
    this.controller = controller;
    this.dialog = controller.element.querySelector(".ysws-shortcuts");
    // Turbo may restore a snapshot taken while this dialog was open.
    this.dialog.close();
    this.abort = new AbortController();
    const options = { signal: this.abort.signal };
    this.dialog.addEventListener(
      "click",
      (event) => this.click(event),
      options,
    );
    this.dialog.addEventListener(
      "submit",
      (event) => {
        event.preventDefault();
        this.save();
      },
      options,
    );
    this.dialog.addEventListener(
      "change",
      (event) => {
        if (event.target.matches('[data-shortcuts="modifier"]')) {
          this.draft.notes_modifier = event.target.value;
          this.cancelRecording();
          this.render();
        }
      },
      options,
    );
    this.dialog.addEventListener(
      "cancel",
      (event) => {
        event.preventDefault();
        if (this.recording) this.cancelRecording();
        else this.close();
      },
      options,
    );
  }

  get open() {
    return this.dialog.open;
  }
  find(name) {
    return this.dialog.querySelector(`[data-shortcuts="${name}"]`);
  }

  show() {
    this.returnFocus = document.activeElement;
    this.draft = structuredClone(this.controller.settingsValue);
    this.draft.bindings ||= {};
    this.render();
    this.dialog.showModal();
  }

  close() {
    if (this.saving) return;
    this.cancelRecording();
    this.dialog.close();
    const target = this.returnFocus?.isConnected
      ? this.returnFocus
      : this.controller.legend;
    target?.focus({ preventScroll: true });
  }

  destroy() {
    clearTimeout(this.recordingTimer);
    this.abort.abort();
    this.dialog.close();
  }

  message(text) {
    this.find("status").textContent = text;
  }

  button(text, command, action, index) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = text;
    button.dataset.command = command;
    button.dataset.actionId = action;
    if (index !== undefined) button.dataset.index = index;
    return button;
  }

  render(focusAction) {
    const { catalogValue: catalog, isMac } = this.controller;
    const normal = bindings(catalog, this.draft);
    const selection = this.draft.notes_modifier || "platform";
    const automatic = isMac ? "Control" : "Alt";
    this.find("modifier").value = selection;
    this.find("modifier").querySelector('[value="platform"]').textContent =
      `Automatic (${automatic})`;
    this.find("notice").textContent =
      selection === "none"
        ? "Only shortcuts with a modifier work while writing notes."
        : `Hold ${automatic} with plain shortcuts while writing notes.`;
    const rows = this.find("rows");
    rows.replaceChildren();
    for (const [id, action] of Object.entries(catalog)) {
      const row = document.createElement("section");
      row.className = "ysws-shortcuts__row";
      const title = document.createElement("h3");
      title.textContent = action.label;
      const controls = document.createElement("div");
      controls.className = "ysws-shortcuts__bindings";
      normal[id].forEach((key, index) => {
        const chip = document.createElement("span");
        chip.className = "ysws-shortcuts__binding";
        const edit = this.button(label(key), "record", id, index);
        edit.setAttribute(
          "aria-label",
          `Replace ${label(key)} for ${action.label}`,
        );
        const remove = this.button("×", "remove", id, index);
        remove.setAttribute(
          "aria-label",
          `Remove ${label(key)} from ${action.label}`,
        );
        chip.append(edit, remove);
        controls.append(chip);
      });
      if (!normal[id].length)
        controls.append(document.createTextNode("Not assigned"));
      const add = this.button("+", "record", id);
      add.setAttribute("aria-label", `Add shortcut for ${action.label}`);
      add.disabled = normal[id].length >= 4;
      controls.append(add);
      if (this.draft.bindings[id])
        controls.append(this.button("Reset", "reset-action", id));
      row.append(title, controls);
      rows.append(row);
    }
    const error = conflict(catalog, this.draft);
    this.message(error || "");
    this.dialog.querySelector('[type="submit"]').disabled = Boolean(error);
    if (focusAction)
      rows
        .querySelector(
          `[data-action-id="${focusAction}"][data-command="record"]`,
        )
        ?.focus();
  }

  click(event) {
    if (this.saving) return;
    const button = event.target.closest("button");
    if (!button) return;
    if (button.dataset.shortcuts === "close") return this.close();
    if (button.dataset.shortcuts === "reset") {
      this.cancelRecording();
      this.draft = { bindings: {}, notes_modifier: "platform" };
      this.render();
      return;
    }
    const { command, actionId, index } = button.dataset;
    if (!command) return;
    this.cancelRecording();
    if (command === "record") {
      this.recording = {
        actionId,
        index: index === undefined ? null : Number(index),
        button,
      };
      button.textContent = "Press a key…";
      this.message("Press a shortcut. Escape cancels.");
      this.recordingTimer = setTimeout(() => {
        this.message("Shortcut not received. Try another.");
      }, 6000);
      return;
    }
    if (command === "reset-action") delete this.draft.bindings[actionId];
    if (command === "remove") {
      const keys = [
        ...bindings(this.controller.catalogValue, this.draft)[actionId],
      ];
      keys.splice(Number(index), 1);
      this.draft.bindings[actionId] = keys;
    }
    this.render(actionId);
  }

  cancelRecording() {
    clearTimeout(this.recordingTimer);
    if (this.recording) {
      const { actionId, index, button } = this.recording;
      button.textContent =
        index === null
          ? "+"
          : label(
              bindings(this.controller.catalogValue, this.draft)[actionId][
                index
              ],
            );
      this.recording = null;
      this.message("Recording cancelled.");
    }
  }

  keydown(event) {
    if (!this.recording || this.saving) return;
    if (event.key === "Tab") return this.cancelRecording();
    if (event.key === "Escape") {
      event.preventDefault();
      return this.cancelRecording();
    }
    if (["Control", "Alt", "Meta", "Shift"].includes(event.key)) return;
    event.preventDefault();
    clearTimeout(this.recordingTimer);
    const key = chordFromEvent(event);
    if (
      !key ||
      (["space", "enter"].includes(key.split("+").at(-1)) && !modified(key))
    ) {
      return this.message(
        "Use a letter, number, +, −, =, _, or ?. Space and Enter need a modifier.",
      );
    }
    if (this.controller.reservedValue.includes(key))
      return this.message(
        "That shortcut is reserved by the browser or text editor. Choose another.",
      );
    const { actionId, index } = this.recording;
    if (actionId === "complete" && !modified(key))
      return this.message(
        "Complete review needs a modifier to prevent accidental completion.",
      );
    const candidate = structuredClone(this.draft);
    const keys = [
      ...bindings(this.controller.catalogValue, candidate)[actionId],
    ];
    if (keys.includes(key))
      return this.message("That action already has this shortcut.");
    if (index === null) keys.push(key);
    else keys[index] = key;
    candidate.bindings[actionId] = keys;
    const error = conflict(this.controller.catalogValue, candidate, actionId);
    if (error) return this.message(error);
    this.recording = null;
    this.draft = candidate;
    this.render(actionId);
    this.message(`${label(key)} assigned. Save to apply your changes.`);
  }

  async save() {
    if (
      this.saving ||
      this.recording ||
      conflict(this.controller.catalogValue, this.draft)
    )
      return;
    this.saving = true;
    const enabledControls = [
      ...this.dialog.querySelectorAll("button, select"),
    ].filter((el) => !el.disabled);
    enabledControls.forEach((el) => (el.disabled = true));
    this.message("Saving to your account…");
    try {
      const response = await fetch(this.controller.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            ?.content,
        },
        body: JSON.stringify({ shortcuts: this.draft }),
      });
      const data = await response.json().catch(() => ({}));
      if (this.abort.signal.aborted) return;
      if (!response.ok || !data.shortcuts)
        throw new Error(
          data.errors?.join(", ") ||
            "Could not save shortcuts. Try again, or reload to check your access.",
        );
      this.controller.settingsValue = data.shortcuts;
      this.controller.refreshHints();
      this.saving = false;
      this.close();
    } catch (error) {
      this.message(
        error.message || "Could not save shortcuts. Please try again.",
      );
    } finally {
      this.saving = false;
      enabledControls.forEach((el) => (el.disabled = false));
    }
  }
}
