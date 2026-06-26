import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { url: { type: String, default: "/search/users.json" } };

  connect() {
    this._dropdown = null;
    this._results = [];
    this._selectedIndex = 0;
    this._mentionStart = null;
    this._debounceTimer = null;

    // The composer hides the real textarea (display:none) and shows a
    // contenteditable div right after it. Detect that and listen on the
    // visible element instead.
    const isHidden = window.getComputedStyle(this.element).display === "none";
    if (isHidden) {
      const sibling = this.element.nextElementSibling;
      if (sibling && sibling.isContentEditable) {
        this._editable = sibling;
        this._isContentEditable = true;
        sibling.addEventListener("input", this._onEditableInput);
        sibling.addEventListener("keydown", this._onEditableKeydown);
        sibling.addEventListener("blur", this._onEditableBlur);
      }
    }
  }

  disconnect() {
    this._hideDropdown();
    if (this._editable) {
      this._editable.removeEventListener("input", this._onEditableInput);
      this._editable.removeEventListener("keydown", this._onEditableKeydown);
      this._editable.removeEventListener("blur", this._onEditableBlur);
    }
  }

  _onEditableInput = () => this.onInput();
  _onEditableKeydown = (e) => this.onKeydown(e);
  _onEditableBlur = () => this.onBlur();

  get _inputElement() {
    return this._editable || this.element;
  }

  _readCursorText() {
    if (this._isContentEditable) {
      const sel = window.getSelection();
      if (!sel || !sel.isCollapsed || sel.rangeCount === 0) return null;
      const range = sel.getRangeAt(0);
      if (!this._editable.contains(range.startContainer)) return null;

      const pre = document.createRange();
      pre.setStart(this._editable, 0);
      pre.setEnd(range.startContainer, range.startOffset);
      return pre.cloneContents().textContent || "";
    }
    return this.element.value.slice(0, this.element.selectionStart);
  }

  onInput() {
    const text = this._readCursorText();
    if (text === null) {
      this._hideDropdown();
      return;
    }

    const mentionMatch = this._findMentionContext(text);

    if (mentionMatch) {
      this._mentionStart = mentionMatch.start;
      this._fetchUsers(mentionMatch.query);
    } else {
      this._hideDropdown();
    }
  }

  onKeydown(event) {
    if (!this._dropdown) return;

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this._selectedIndex = Math.min(
          this._selectedIndex + 1,
          this._results.length - 1,
        );
        this._highlightSelected();
        break;
      case "ArrowUp":
        event.preventDefault();
        this._selectedIndex = Math.max(this._selectedIndex - 1, 0);
        this._highlightSelected();
        break;
      case "Enter":
      case "Tab":
        if (this._results.length > 0) {
          event.preventDefault();
          event.stopPropagation();
          this._selectUser(this._results[this._selectedIndex]);
        }
        break;
      case "Escape":
        this._hideDropdown();
        break;
    }
  }

  onBlur() {
    setTimeout(() => this._hideDropdown(), 200);
  }

  _findMentionContext(textBeforeCursor) {
    const match = textBeforeCursor.match(/(^|[\s(])@([a-zA-Z0-9_-]*)$/);
    if (!match) return null;

    return {
      start: textBeforeCursor.length - match[2].length - 1,
      query: match[2],
    };
  }

  _fetchUsers(query) {
    clearTimeout(this._debounceTimer);
    this._debounceTimer = setTimeout(async () => {
      try {
        const response = await fetch(
          `${this.urlValue}?q=${encodeURIComponent(query)}`,
        );
        if (!response.ok) return;

        this._results = await response.json();
        this._selectedIndex = 0;

        if (this._results.length > 0) {
          this._showDropdown();
        } else {
          this._hideDropdown();
        }
      } catch {
        this._hideDropdown();
      }
    }, 150);
  }

  _showDropdown() {
    if (!this._dropdown) {
      this._dropdown = document.createElement("div");
      this._dropdown.className = "mention-autocomplete";

      const el = this._inputElement;
      const parent = el.parentElement;
      if (parent) {
        parent.style.position = "relative";
        parent.insertBefore(this._dropdown, el.nextSibling);
      } else {
        document.body.appendChild(this._dropdown);
      }
    }

    this._dropdown.innerHTML = this._results
      .map(
        (user, i) =>
          `<button type="button" class="mention-autocomplete__item ${i === this._selectedIndex ? "mention-autocomplete__item--selected" : ""}" data-index="${i}">
          <img src="${this._avatarUrl(user)}" alt="" class="mention-autocomplete__avatar" />
          <span class="mention-autocomplete__name">@${this._escapeHtml(user.display_name)}</span>
        </button>`,
      )
      .join("");

    this._dropdown
      .querySelectorAll(".mention-autocomplete__item")
      .forEach((el) => {
        el.addEventListener("mousedown", (e) => {
          e.preventDefault();
          const index = parseInt(el.dataset.index, 10);
          this._selectUser(this._results[index]);
        });
      });
  }

  _hideDropdown() {
    if (this._dropdown) {
      this._dropdown.remove();
      this._dropdown = null;
    }
    this._results = [];
    this._mentionStart = null;
  }

  _highlightSelected() {
    if (!this._dropdown) return;
    this._dropdown
      .querySelectorAll(".mention-autocomplete__item")
      .forEach((el, i) => {
        el.classList.toggle(
          "mention-autocomplete__item--selected",
          i === this._selectedIndex,
        );
      });
  }

  _selectUser(user) {
    if (!user || this._mentionStart === null) return;

    const mention = `@${user.display_name} `;

    if (this._isContentEditable) {
      this._insertIntoContentEditable(mention);
    } else {
      const textarea = this.element;
      const before = textarea.value.slice(0, this._mentionStart);
      const after = textarea.value.slice(textarea.selectionStart);
      textarea.value = before + mention + after;
      const cursorPos = before.length + mention.length;
      textarea.setSelectionRange(cursorPos, cursorPos);
      textarea.focus();
    }

    this._hideDropdown();
  }

  _insertIntoContentEditable(mention) {
    const sel = window.getSelection();
    if (!sel || !sel.isCollapsed || sel.rangeCount === 0) return;

    const range = sel.getRangeAt(0);
    const node = range.startContainer;
    if (node.nodeType !== Node.TEXT_NODE) return;

    const text = node.textContent;
    const before = text.slice(0, range.startOffset);
    const triggerMatch = before.match(/@[a-zA-Z0-9_-]*$/);
    if (!triggerMatch) return;

    const triggerStart = before.length - triggerMatch[0].length;
    const after = text.slice(range.startOffset);

    node.textContent = text.slice(0, triggerStart) + mention + after;

    const newRange = document.createRange();
    newRange.setStart(node, triggerStart + mention.length);
    newRange.collapse(true);
    sel.removeAllRanges();
    sel.addRange(newRange);

    this._editable.dispatchEvent(new Event("input", { bubbles: true }));
  }

  _avatarUrl(user) {
    if (user.avatar) return user.avatar;
    if (user.slack_id)
      return `https://cachet.dunkirk.sh/users/${user.slack_id}/r`;
    return "";
  }

  _escapeHtml(text) {
    const el = document.createElement("span");
    el.textContent = text;
    return el.innerHTML;
  }
}
