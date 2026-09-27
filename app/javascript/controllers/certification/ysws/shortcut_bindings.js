const KEY_NAMES = {
  " ": "space",
  Enter: "enter",
  "=": "equals",
  "+": "plus",
  "-": "minus",
  _: "underscore",
  "?": "question",
};
const LABELS = {
  ctrl: "Ctrl",
  alt: "Alt",
  shift: "Shift",
  meta: "Meta",
  space: "Space",
  enter: "Enter",
  equals: "=",
  plus: "+",
  minus: "−",
  underscore: "_",
  question: "?",
};

export function chordFromEvent(event) {
  const key =
    KEY_NAMES[event.key] ||
    (/^[a-z0-9]$/i.test(event.key) ? event.key.toLowerCase() : null);
  if (!key) return null;
  // Printable symbols already include their Shift transformation. Keeping a
  // second Shift bit would give the same symbol two different identities.
  const shift =
    event.shiftKey &&
    !["equals", "plus", "minus", "underscore", "question"].includes(key);
  return [
    event.ctrlKey && "ctrl",
    event.altKey && "alt",
    shift && "shift",
    event.metaKey && "meta",
    key,
  ]
    .filter(Boolean)
    .join("+");
}

export function modified(chord) {
  return chord
    .split("+")
    .some((part) => ["ctrl", "alt", "meta"].includes(part));
}

export function label(chord) {
  return chord
    .split("+")
    .map((part) => LABELS[part] || part.toUpperCase())
    .join("+");
}

export function bindings(catalog, settings, mac = false, inNotes = false) {
  const modifier =
    settings.notes_modifier === "none" ? "none" : mac ? "ctrl" : "alt";
  return Object.fromEntries(
    Object.entries(catalog).map(([id, action]) => {
      const keys = settings.bindings?.[id] ?? action.bindings;
      return [
        id,
        inNotes
          ? [
              ...new Set(
                keys.flatMap((key) => {
                  if (modified(key)) return [key];
                  return action.notes && modifier !== "none"
                    ? [`${modifier}+${key}`]
                    : [];
                }),
              ),
            ]
          : keys,
      ];
    }),
  );
}

export function conflict(catalog, settings, editingAction = null) {
  for (const mac of [false, true]) {
    for (const inNotes of [false, true]) {
      const used = new Map();
      for (const [id, keys] of Object.entries(
        bindings(catalog, settings, mac, inNotes),
      )) {
        for (const key of keys) {
          if (used.has(key) && used.get(key) !== id) {
            const other = used.get(key) === editingAction ? id : used.get(key);
            return `${label(key)} is already assigned to ${catalog[other].label}${inNotes ? " in notes" : ""}.`;
          }
          used.set(key, id);
        }
      }
    }
  }
  return null;
}
