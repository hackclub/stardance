import { Controller } from "@hotwired/stimulus";
import emojiData from "@emoji-mart/data";

const MAX_SUGGESTIONS = 8;
const SHORTCODE_MATCH = /(^|\s):([a-z0-9_+-]{1,40})$/i;
const COMPLETE_SHORTCODE_MATCH = /:([a-z0-9_+-]{1,40}):/gi;
const ID_PATTERN = /^[a-z0-9_+-]+$/i;

const DEFAULT_ALIASES_BY_EMOJI = Object.entries(emojiData.aliases || {}).reduce(
  (aliases, [alias, id]) => {
    aliases[id] ||= [];
    aliases[id].push(alias);
    return aliases;
  },
  {},
);

const DEFAULT_EMOTES = Object.values(emojiData.emojis).flatMap((emote) => {
  const native = emote.skins?.[0]?.native;
  if (!native || !ID_PATTERN.test(emote.id)) return [];

  const aliases = DEFAULT_ALIASES_BY_EMOJI[emote.id] || [];
  return normalizeEmote({
    id: emote.id,
    native,
    shortcodes: [emote.id, ...aliases],
    searchText: searchText(emote.id, emote.name, emote.keywords, aliases),
  });
});

const DEFAULT_BY_SHORTCODE = new Map(
  DEFAULT_EMOTES.flatMap((emote) =>
    emote.shortcodes.map((shortcode) => [shortcode, emote]),
  ),
);

let customEmotes = [];
let customById = new Map();
let customCategory = [];
let customEmotesPromise = null;

function normalizeEmote(emote) {
  return {
    ...emote,
    shortcodes: emote.shortcodes.map((shortcode) => shortcode.toLowerCase()),
  };
}

function searchText(...parts) {
  return parts.flat().filter(Boolean).join(" ").toLowerCase();
}

function safeEmoteSrc(emote) {
  try {
    const url = new URL(emote.skins?.[0]?.src || "");
    return url.protocol === "https:" ? url.href : null;
  } catch {
    return null;
  }
}

async function loadCustomEmotes() {
  customEmotesPromise ||= fetch("/slack_emotes.json")
    .then((response) => (response.ok ? response.json() : []))
    .catch(() => [])
    .then((emotes) => {
      customEmotes = emotes.flatMap((emote) => {
        const src = safeEmoteSrc(emote);
        if (!src || !ID_PATTERN.test(emote.id)) return [];

        return normalizeEmote({
          ...emote,
          id: emote.id,
          src,
          skins: [{ src }],
          shortcodes: [emote.id],
          searchText: searchText(emote.id, emote.keywords),
        });
      });
      customById = new Map(
        customEmotes.map((emote) => [emote.id.toLowerCase(), emote]),
      );
      customCategory = customEmotes.length
        ? [{ id: "slack", name: "Slack", emojis: customEmotes }]
        : [];
    });

  return customEmotesPromise;
}

export default class extends Controller {
  static targets = ["editor", "trigger", "popover", "textarea"];

  #picker = null;
  #pickerOpen = false;
  #menu = null;
  #matches = [];
  #selected = 0;
  #range = null;

  async connect() {
    if (this.hasEditorTarget && this.hasTextareaTarget) {
      await loadCustomEmotes();
      this.#renderEditor(
        this.textareaTarget.value,
        this.textareaTarget.value.length,
      );
    }
  }

  disconnect() {
    this.close();
    this.#hideSuggestions();
    this.#picker = null;
    this.#menu = null;
  }

  toggle() {
    this.hasPopoverTarget && !this.popoverTarget.hidden
      ? this.close()
      : this.open();
  }

  async open() {
    if (!this.hasPopoverTarget) return;

    this.#hideSuggestions();
    await loadCustomEmotes();
    if (!this.#picker) {
      const { Picker } = await import("emoji-mart");
      const data = (await import("@emoji-mart/data")).default;

      this.#picker = new Picker({
        data,
        custom: customCategory,
        onEmojiSelect: (emoji) =>
          this.#insertEmote(emoji.native || (emoji.id ? `:${emoji.id}:` : "")),
        theme: "dark",
        set: "native",
        previewPosition: "none",
        skinTonePosition: "search",
        maxFrequentRows: 2,
      });

      this.popoverTarget.appendChild(this.#picker);
    }

    this.#setPickerOpen(true);
    document.addEventListener("click", this.#outsideClick, true);
    document.addEventListener("keydown", this.#escHandler);
  }

  close() {
    this.#pickerOpen = false;
    if (this.#picker) this.#picker.hidden = true;
    if (this.#menu) this.#menu.hidden = true;
    if (this.hasPopoverTarget) this.popoverTarget.hidden = true;
    document.removeEventListener("click", this.#outsideClick, true);
    document.removeEventListener("keydown", this.#escHandler);
  }

  async editorInput() {
    await loadCustomEmotes();
    const cursor = this.#editorOffset();
    const resolved = this.#resolveShortcodes(
      this.#rawText(this.editorTarget),
      cursor,
    );
    this.#setTextareaValue(resolved.value);
    this.#renderEditor(resolved.value, resolved.cursor);
    this.#refreshSuggestions(resolved.cursor);
  }

  editorKeydown(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      this.editorTarget.closest("form")?.requestSubmit();
      return;
    }

    if (!this.#suggestionsVisible()) return;

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const step = event.key === "ArrowDown" ? 1 : -1;
      this.#selected =
        (this.#selected + step + this.#matches.length) % this.#matches.length;
      this.#renderSuggestions();
    } else if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault();
      this.#completeSuggestion(this.#selected);
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.#hideSuggestions();
    }
  }

  editorBlur() {
    setTimeout(() => this.#hideSuggestions(), 120);
  }

  #outsideClick = (event) => {
    if (
      this.hasPopoverTarget &&
      !this.popoverTarget.contains(event.target) &&
      !this.triggerTarget.contains(event.target)
    ) {
      this.close();
    }
  };

  #escHandler = (event) => {
    if (event.key === "Escape") this.close();
  };

  async #refreshSuggestions(cursor) {
    await loadCustomEmotes();
    const range = this.#shortcodeRange(cursor);
    if (!range) return this.#hideSuggestions();

    const query = range.query.toLowerCase();
    const matches = [...customEmotes, ...DEFAULT_EMOTES]
      .filter((emote) => emote.searchText.includes(query))
      .sort((a, b) => this.#score(a, query) - this.#score(b, query))
      .slice(0, MAX_SUGGESTIONS);

    if (matches.length === 0) return this.#hideSuggestions();

    this.#range = range;
    this.#matches = matches;
    this.#selected = 0;
    this.#renderSuggestions();
  }

  #renderSuggestions() {
    const menu = this.#suggestionsMenu();
    menu.innerHTML = this.#matches
      .map(
        (emote, index) => `
          <button type="button"
                  class="feed-composer__emote-suggestion"
                  data-index="${index}"
                  data-active="${index === this.#selected}">
            ${this.#suggestionIcon(emote)}
            <span class="feed-composer__emote-suggestion-code">:${emote.id}:</span>
          </button>
        `,
      )
      .join("");
    this.#setPickerOpen(false);
    this.popoverTarget.hidden = false;
    menu.hidden = false;
  }

  #suggestionsMenu() {
    if (this.#menu) return this.#menu;

    this.#menu = document.createElement("div");
    this.#menu.className = "feed-composer__emote-suggestions";
    this.#menu.hidden = true;
    this.#menu.role = "listbox";
    this.#menu.addEventListener("mousedown", (event) => event.preventDefault());
    this.#menu.addEventListener("click", (event) => {
      const option = event.target.closest("[data-index]");
      if (option) this.#completeSuggestion(Number(option.dataset.index));
    });
    this.popoverTarget.prepend(this.#menu);
    return this.#menu;
  }

  #completeSuggestion(index) {
    const emote = this.#matches[index];
    if (!emote || !this.#range) return;

    this.#insertEmote(emote.native || `:${emote.id}:`, this.#range);
    this.#hideSuggestions();
  }

  #insertEmote(text, range = null) {
    if (!this.hasTextareaTarget || !text) return;

    const start = range?.start ?? this.#editorOffset();
    const end = range?.end ?? start;
    const after = this.textareaTarget.value.slice(end);
    const insert = `${text}${after.startsWith(" ") ? "" : " "}`;
    const value = this.textareaTarget.value.slice(0, start) + insert + after;
    const cursor = start + insert.length;

    this.#setTextareaValue(value);
    this.#renderEditor(value, cursor);
    this.#refreshSuggestions(cursor);
    this.editorTarget.focus();
  }

  #resolveShortcodes(value, cursor) {
    let nextCursor = cursor;
    const resolved = value.replace(
      COMPLETE_SHORTCODE_MATCH,
      (match, code, offset, source) => {
        const defaultEmote = DEFAULT_BY_SHORTCODE.get(code.toLowerCase());
        const customEmote = customById.get(code.toLowerCase());
        if (!defaultEmote && !customEmote) return match;

        const next = source[offset + match.length];
        const insert = `${defaultEmote?.native || match}${next === " " ? "" : " "}`;
        const delta = insert.length - match.length;

        if (offset < cursor && cursor <= offset + match.length) {
          nextCursor = offset + insert.length;
        } else if (offset + match.length <= cursor) {
          nextCursor += delta;
        }

        return insert;
      },
    );

    return { value: resolved, cursor: nextCursor };
  }

  #renderEditor(value, cursor = value.length) {
    if (!this.hasEditorTarget) return;

    this.editorTarget.replaceChildren(...this.#editorNodes(value));
    this.#setEditorOffset(cursor);
  }

  #editorNodes(value) {
    const nodes = [];
    let cursor = 0;

    value.replace(COMPLETE_SHORTCODE_MATCH, (match, code, offset) => {
      const emote = customById.get(code.toLowerCase());
      if (!emote) return match;

      if (offset > cursor) {
        nodes.push(document.createTextNode(value.slice(cursor, offset)));
      }

      const img = document.createElement("img");
      img.className = "feed-composer__emote-inline";
      img.src = emote.src;
      img.alt = match;
      img.title = match;
      img.dataset.shortcode = code;
      img.contentEditable = "false";
      nodes.push(img);
      cursor = offset + match.length;
      return match;
    });

    if (cursor < value.length) {
      nodes.push(document.createTextNode(value.slice(cursor)));
    }

    return nodes;
  }

  #rawText(node) {
    if (node.nodeType === Node.TEXT_NODE) return node.textContent;
    if (node.nodeName === "IMG") {
      return node.dataset.shortcode ? `:${node.dataset.shortcode}:` : "";
    }
    return [...node.childNodes].map((child) => this.#rawText(child)).join("");
  }

  #editorOffset() {
    const selection = window.getSelection();
    if (
      !selection?.rangeCount ||
      !this.editorTarget.contains(selection.anchorNode)
    ) {
      return this.textareaTarget.value.length;
    }

    const range = document.createRange();
    range.selectNodeContents(this.editorTarget);
    range.setEnd(selection.anchorNode, selection.anchorOffset);
    return this.#nodeRawLength(range.cloneContents());
  }

  #setEditorOffset(offset) {
    const range = document.createRange();
    const selection = window.getSelection();
    let remaining = offset;

    const place = (node) => {
      if (node.nodeType === Node.TEXT_NODE) {
        const position = Math.min(remaining, node.textContent.length);
        range.setStart(node, position);
        return true;
      }

      if (node.nodeName === "IMG") {
        range.setStartAfter(node);
        return true;
      }

      for (const child of node.childNodes) {
        const length = this.#nodeRawLength(child);
        if (remaining <= length) return place(child);
        remaining -= length;
      }

      range.selectNodeContents(node);
      range.collapse(false);
      return true;
    };

    place(this.editorTarget);
    range.collapse(true);
    selection.removeAllRanges();
    selection.addRange(range);
  }

  #nodeRawLength(node) {
    return this.#rawText(node).length;
  }

  #setTextareaValue(value) {
    this.textareaTarget.value = value;
    this.textareaTarget.dispatchEvent(new Event("input", { bubbles: true }));
  }

  #shortcodeRange(cursor) {
    const match = this.textareaTarget.value
      .slice(0, cursor)
      .match(SHORTCODE_MATCH);
    if (!match) return null;

    return {
      start: cursor - match[2].length - 1,
      end: cursor,
      query: match[2],
    };
  }

  #score(emote, query) {
    if (emote.shortcodes.includes(query)) return 0;
    if (emote.shortcodes.some((shortcode) => shortcode.startsWith(query)))
      return 1;
    return 2;
  }

  #suggestionIcon(emote) {
    if (emote.src) {
      return `<img class="feed-composer__emote-suggestion-image" src="${emote.src}" alt="" loading="lazy">`;
    }

    return `<span class="feed-composer__emote-suggestion-native">${emote.native}</span>`;
  }

  #setPickerOpen(open) {
    this.#pickerOpen = open;
    if (this.#picker) this.#picker.hidden = !open;
    if (this.hasPopoverTarget) {
      this.popoverTarget.hidden = !open && !this.#suggestionsVisible();
    }
  }

  #hideSuggestions() {
    if (this.#menu) this.#menu.hidden = true;
    this.#matches = [];
    this.#range = null;
    this.#setPickerOpen(this.#pickerOpen);
  }

  #suggestionsVisible() {
    return this.#menu && !this.#menu.hidden;
  }
}
