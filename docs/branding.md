# Stardance branding

Authoritative reference for the Stardance visual identity: colors, typography,
containers, buttons, and forms. Sourced from the Figma "design system" page in
[the empty space above](https://www.figma.com/design/0SKWTBoX3TSGPfF1SOAQBL/the-empty-space-above?node-id=4473-6469)
(node `4473:6469`).

This doc is the source of truth. The CSS tokens in
[app/assets/stylesheets/config/_variables.scss](../app/assets/stylesheets/config/_variables.scss)
should follow what's here. When the code and this doc disagree, the doc wins —
unless the code is being intentionally moved first, in which case update the
doc in the same PR.

For agents: the brief version is in [AGENTS.md](../AGENTS.md#stardance-themeing).
Read this doc when you need details beyond the brief — typography sizing,
button states, container semantics, which set/accent applies in a given
context.

---

## Quick reference

1. Never use pure black. Use set 1 background `#08061E`.
2. Pick colors from the palette. If you need a new color, stay pastel.
3. Page background defaults to set 1 (`#08061E`). Use sets 2–4 for containers
   within the page.
4. Body text: white (`#FFFFFF`). Muted text: the secondary-foreground of the
   set you're sitting on.
5. Exo 2 everywhere; Playfair Display bold-italic only for Title / Title 2 as
   editorial emphasis.
6. Containers: 8px radius, 2px borders when present. Buttons: fully rounded
   pills.
7. **Primary action buttons fill with `--color-brand-highlight` (`#F4EBB9`),
   not yellow.** Yellow `#FFE564` is *only* used inside
   `--gradient-extra-highlight` (see §1.2).
8. Salmon `#FF8D9D` signals warn / destructive.
9. Orange `#FFB07A` (dashed border) is the **admin / manageable-by-viewer
   marker** — see §1.5. Never use it for anything else.
10. Disabled = 50% opacity over the normal state — don't invent a separate
    disabled color.
11. CSS lives in `app/assets/stylesheets/`, all selectors follow BEM
    (`block / block__element / block--modifier`). Reference design tokens via
    `var(--token-name)`, not inline hex.

---

## 1. Colors

The palette splits into four families:

| Family | Purpose |
| --- | --- |
| **Sets 1–4** | Surfaces: page background + container fills, paired with their own foreground text colors. |
| **Highlights** | Quiet attention-grabbers (callouts, toasts, badges) that aren't full accents. |
| **Accents 1–6** | The expressive pastel palette — used sparingly for emphasis, illustrations, status, branded surfaces. |
| **Foreground** | Pure white text used on dark sets. |

Never use pure black (`#000000`); the darkest color in the system is set 1's
background, `#08061E`. When in doubt, pick from the palette below. If you must
go outside it, stay pastel — avoid deep saturated colors that fight with the
rest of the system.

### 1.1 Sets (containers + their text)

Each set is a `(background, secondary-foreground)` pair. The primary foreground
is always `#FFFFFF`. Use `secondary-foreground` for muted/secondary text on top
of that set's background.

| Set | Background | Secondary foreground | Where to use |
| --- | --- | --- | --- |
| **Set 1** — main | `#08061E` | `#83828D` | Page background. Containers with lots of text: posts, notifications, comments. Default surface. |
| **Set 2** — dark blue | `#343651` | `#83828D` | Cards that are themselves interactive: project cards, clickable cards. |
| **Set 3** — solid blue | `#606684` | `#AFB2C1` | Profile sections, top-of-page cards. The "lifted" surface. |
| **Set 4** — highlighted | `#66625C` | `#B3B1AD` | Highlighted posts/cards that need attention (e.g. featured "latest ship"). Numerically the canonical highlight cream (`#FEFCE7`) at ~40% alpha over set 1 — warm-gray that pairs with a cream highlight border. |

### 1.2 Highlights

For badges, callouts, toast strips, light-on-dark emphasis — not full accents,
not container surfaces. They live on top of set 1 / set 2.

| Token | Hex | Notes |
| --- | --- | --- |
| **Highlight** | `#F4EBB9` | Soft golden yellow. |
| **Secondary highlight** | `#FEFCE7` | Near-white cream — quieter alternative to `Highlight`. |

#### Extra highlight — the four-corner gradient

A mesh blend of four brand accents (yellow → salmon along the top, lilac →
brand-blue along the bottom). CSS radial-gradients can't reproduce the mesh
faithfully, so the canonical asset is a PNG at
[`app/assets/images/gradients/extra-highlight.png`](../app/assets/images/gradients/extra-highlight.png),
exposed as `--gradient-extra-highlight`.

**At most one or two on a page.** This is the loudest surface the system
offers — reserve it for moments that deserve genuine spectacle (a Super-Star
Project chip, a hero badge, a once-per-page celebration). On every other
surface, use the regular accents or highlights.

The token resolves to a `url(...)`, so the consumer sets sizing. Always use
the background shorthand so the asset covers the element and is centred:

```scss
background: var(--gradient-extra-highlight) center / cover no-repeat;
color:      var(--color-set-1-bg); // dark ink on a bright pastel
```

Example uses today: `.project-show__badge--fire` (Super-Star Project chip).

### 1.3 Accents

Six pastels for branded surfaces, illustrations, status colors, and any
"colored area" decision. Reach for these before inventing new HSL tints.

| Token | Hex | Common role |
| --- | --- | --- |
| **Accent 1** — peach | `#FFD598` | Warm, gentle emphasis. |
| **Accent 2** — yellow | `#FFE564` | Stars, special-action button fill, "important". |
| **Accent 3** — salmon | `#FF8D9D` | Warn / destructive accents. |
| **Accent 4** — blue | `#95DBFF` | Cool emphasis. |
| **Accent 5** — lilac | `#EBB7FF` | Default primary accent. |
| **Accent 6** — mint | `#81FFFF` | Cool emphasis, "online"/"active" states. |

### 1.4 Mapping to CSS variables

These tokens already exist in
[_variables.scss](../app/assets/stylesheets/config/_variables.scss). When you
write SCSS, reference the variable, not the hex.

| Doc token | CSS variable | Status |
| --- | --- | --- |
| Set 1 background `#08061E` | `--color-space-bg` | Currently defined as `hsl(245, 55%, 8%)` — approximately the same but not pixel-exact. Prefer the variable; use the hex when an exact match matters. |
| Set 1–4 backgrounds | `--color-set-1-bg` … `--color-set-4-bg` | ✓ exact |
| Set N secondary foregrounds | _(no variables yet)_ | Add `--color-set-N-fg-secondary` when first needed. |
| Accent 1 peach `#FFD598` | `--color-brand-peach` | ✓ exact |
| Accent 2 yellow `#FFE564` | `--color-brand-yellow` | ✓ exact |
| Accent 3 salmon `#FF8D9D` | `--color-brand-salmon` | ✓ exact |
| Accent 4 blue `#95DBFF` | `--color-brand-blue` | ✓ exact |
| Accent 5 lilac `#EBB7FF` | `--color-brand-lilac` | ✓ exact |
| Accent 6 mint `#81FFFF` | `--color-brand-mint` | ✓ exact |
| Admin marker orange `#FFB07A` | `--color-brand-orange` | ✓ exact (also `--color-brand-orange-soft` α 0.18). Not in the Figma palette — added for §1.5. |
| Highlight `#F4EBB9` | `--color-brand-highlight` | ✓ exact (also `--color-brand-highlight-soft` α 0.4 and `-faint` α 0.12) |
| Secondary highlight `#FEFCE7` | `--color-brand-highlight-secondary` | ✓ exact |
| Extra-highlight gradient | `--gradient-extra-highlight` | Four-stop radial blend — yellow / salmon / lilac / blue. Use as the value of `background:` (not `background-color`). |

### 1.5 Admin / staff-only marking

Some surfaces are visible to a user *because* they have elevated permissions
on the underlying thing — an admin viewing every mission, an owner seeing
their own draft mission on the public events page, a manager viewing a
project they reviewed. Those surfaces need a visual cue that says "this is
shown to you, but it isn't public chrome", without hijacking the action
language reserved for warn / destructive (salmon) or primary action
(highlight cream).

**The convention:**

| Element | Treatment |
| --- | --- |
| **Border** | `2px dashed var(--color-brand-orange)` (`#FFB07A`). The dashed style does most of the semantic work — it signals "draft-ish / not finished / not for everyone". |
| **Companion pills / chips** | `var(--color-brand-orange-soft)` background, `var(--color-brand-orange)` text. Bold, uppercase, letter-spaced — same shape as a status pill. Optional but encouraged when the user might wonder *why* a thing is visible to them ("Draft", "Disabled", "Admin-only", etc.). |
| **Hover** | Keep the orange dashed border on hover instead of switching to the regular accent hover — the marker is a *state* of the item, not a per-interaction effect. |

**When to use it**

- A card / row / panel surfaced to the viewer purely because they can
  manage it (admin role or membership-based ownership), and which other
  viewers wouldn't see.
- A surface in the public part of the app that's mid-draft, disabled, or
  otherwise pre-publication and is being revealed to its managers.

**When NOT to use it**

- General "internal" or "admin section" pages (`/admin/...`). Those live
  behind their own URL and already read as off-product; they don't need
  per-element marking.
- Destructive controls — that's salmon's job (§1.3).
- "You are the author / owner" markers on otherwise-public content where
  the affordance is *editing*, not *managing visibility*. Use a regular
  edit pill instead.

**How to apply in code**

```scss
.thing--manageable {
  border-style: dashed;
  border-width: 2px;
  border-color: var(--color-brand-orange);

  &:hover,
  &:focus-visible {
    border-color: var(--color-brand-orange);
  }
}

.thing__pill--draft {
  background: var(--color-brand-orange-soft);
  color: var(--color-brand-orange);
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
```

Existing usages: `.mission-card--manageable` +
`.mission-card__meta-item--draft` on the events page.

---

## 2. Typography

Two type families:

- **Exo 2** — the workhorse. All body, headings, labels.
- **Playfair Display** — italic emphasis variant for Title and Title 2. Adds
  editorial weight to the largest type. Always bold italic.

### 2.1 Scale

| Role | Font | Size | Weight | Casing | Use for |
| --- | --- | --- | --- | --- | --- |
| **Title** | Exo 2 _or_ Playfair Display _bold italic_ | 70px | Bold | normal | Hero-level page titles (one per page max). Playfair is the editorial flourish; Exo 2 is the plain variant. Pick one per title. |
| **Title 2** | Exo 2 _or_ Playfair Display _bold italic_ | 56px | Bold | normal | Secondary page titles, large section titles, modal titles. Same Exo/Playfair pairing as Title. |
| **Heading** | Exo 2 | 40px | Bold | normal | Section headings inside a page. |
| **Small heading** | Exo 2 | 19px | Bold | **ALL CAPS** | Subsection / group labels above lists or cards. The all-caps cue distinguishes it from Body at the same size. |
| **Body** | Exo 2 | 19px | Regular | normal | Default page text. |
| **Label** | Exo 2 | 16px | Regular | normal | Form labels, captions, metadata, fine print. |

### 2.2 Notes

- **Italics at title sizes only.** Don't introduce Playfair at smaller sizes,
  and don't italicize Exo 2 as a substitute. The italic moment is reserved.
- **Playfair fallback:** `"Times New Roman", Georgia, serif` so the italic
  feel survives (already the pattern in `_hero.scss` and the sidebar's
  active-nav label).
- **Exo 2 fallback:** `"Exo 2", sans-serif` — system sans is fine if Exo 2 is
  missing.
- **Line height:** `--line-height-headers: 1.1` for headings, `normal` for
  body.
- **Mobile:** Body shrinks to 16px below 600px viewport width (see the
  `@media (max-width: 600px)` block in `_variables.scss`). The landing scale
  (`--font-display`, `--font-h2`, `--font-h3`, `--font-body`, `--font-subtitle`)
  is fluid-clamped — use those on landing pages instead of the fixed scale
  above.

---

## 3. Containers

All containers use an **8px corner radius** and **2px borders** (where a
border is present). Four standard "set" variants plus one special case.

| Variant | Border | Background | Use for |
| --- | --- | --- | --- |
| **Main container** (set 1) | 2px | `#08061E` | Posts, notifications, comments — anywhere with a lot of text. Default container. |
| **Dark blue container** (set 2) | 2px | `#343651` | Project cards and other clickable cards. The presence of a border signals "you can click me." |
| **Solid blue container** (set 3) | _none_ | `#606684` | Profile sections, top-of-page cards. No border because they sit above the page surface visually. |
| **Highlighted container** (set 4) | 2px | `#66625C` | Highlighted posts/cards that need to stand out — warmer tone than the blues. Pairs naturally with a `--color-brand-highlight` border. |

**Border color.** When a set has a 2px border, the border color matches the
container's secondary-foreground (the muted text color) — this gives the edge
the same "muted" feel as the supporting text inside.

**Invisible container.** When a container shouldn't visually separate from its
parent surface, set its background to the same hex as the surface it's sitting
on (set 1, 2, or 3). Don't use `transparent` — pick the matching hex
explicitly so the container still renders predictably when copy-pasted or
moved.

---

## 4. Buttons

Three button types: **small action**, **large action**, **special action**.
All three use **fully rounded corners** (pill shape — `border-radius` = half
the height).

### 4.1 Background-aware variants

Every button has two visual variants, picked based on the surface the button
sits on:

| Variant | Use on which sets | Why |
| --- | --- | --- |
| **Dark-bg variant** | Set 1 (`#08061E`) and set 2 (`#343651`) | Primary fills lean cream/highlight to pop against the dark surface. |
| **Light-bg variant** | Set 3 (`#606684`) and set 4 (`#66625C`) | Primary fills lean white because the cream highlight blends into set 3/4. |

Match the variant to the **immediate parent surface**, not the page
background. A pill inside a set-3 panel uses the light-bg variant even though
the page itself is set 1.

The state matrices in 4.2–4.4 list the **dark-bg** variant (used on most
pages). The light-bg variant follows the same pattern but pushes Normal one
step lighter (`brand-highlight` → `brand-highlight-secondary` or `white`).

**Approved backgrounds.** Small buttons and large secondary buttons are tuned
for set 1 / set 2. Large primary (yellow) and special action stay legible on
any set because their fill is bright. If you put a small button on set 3 or
set 4, retest contrast.

### 4.2 Small action buttons

- **Text:** 16px, bold.
- **Border:** 2px.
- **Padding:** 16px horizontal, 3px vertical.
- **Used for:** Edit profile / Edit post, Save and discard on profile / posts,
  confirmation popups, follow / unfollow.
- **Hover:** at this size there's no end icon, so hover just shifts the fill.

**Dark-bg variants & states:**

| | Normal | Hover | Pressed | Disabled |
| --- | --- | --- | --- | --- |
| **Primary** — *filled* | `--color-brand-highlight` (`#F4EBB9`) fill, `--color-set-1-bg` text, no border | `--color-brand-highlight-secondary` (`#FEFCE7`) fill | white fill | `opacity: 0.5` over normal |
| **Secondary** — *outlined* | `--color-set-2-bg` fill, white text, white 2px border | same fill, icon transition | same fill, `--color-brand-highlight` text + border | `opacity: 0.5` over normal |
| **Destructive** | transparent fill, `--color-brand-salmon` text + 2px border | `--color-brand-salmon` fill, `--color-set-1-bg` text | `--color-brand-salmon` fill, dark text (slightly washed) | `opacity: 0.5` over normal |

**Light-bg overrides** (inside a set-3 or set-4 surface):

- **Primary** reverses on a light bg, stepping *darker* with each interaction
  so pressing reads as "more filled":
  - Normal: white fill (`--color-space-text`)
  - Hover: `--color-brand-highlight-secondary` (`#FEFCE7`)
  - Pressed: `--color-brand-highlight` (`#F4EBB9`)
  - Disabled: opacity 0.5
- **Secondary** normal swaps the set-2 fill → transparent so the surrounding
  surface shows through; border stays white-on-set-3 or dark-text-on-set-4.
- Destructive unchanged.

### 4.3 Large action buttons

- **Text:** 19px, bold.
- **Border:** 2px.
- **Padding:** ≥32px horizontal _or_ fill the row horizontally; 12px vertical.
- **End icon:** optional. When present, **the icon translates right on
  hover** (the button body itself doesn't move).
- **Used for:** the primary action on a page or modal — "Post a devlog",
  "Create new ship", external link buttons like "Try project" / "See source
  code".

**Dark-bg variants & states:**

| | Normal | Hover | Pressed | Disabled |
| --- | --- | --- | --- | --- |
| **Primary** — *filled* | `--color-brand-highlight` (`#F4EBB9`) fill, dark text, no border (border-color matches fill) | `--color-brand-highlight-secondary` (`#FEFCE7`) fill | white fill | `opacity: 0.5` over normal |
| **Secondary** — *outlined* | `--color-set-2-bg` fill, white text, white 2px border | same fill, end-icon translates right | same fill, `--color-brand-highlight` text + border | `opacity: 0.5` over normal |

**Light-bg overrides:**

- **Primary** uses the same darker-on-press ladder as small action: white →
  `--color-brand-highlight-secondary` → `--color-brand-highlight`.
- **Secondary** normal keeps the white border + white text but drops the fill
  to transparent.

### 4.4 Special action button

- **Shape:** the pill sits inside a **star symbol** outline — the rounded-rect
  pill overlaps a star shape so a few of the star's points peek out behind
  it. The star and the pill share the same fill colour at every state.
- **Text:** 19px, bold.
- **Border:** the pill itself has a 2px transparent border (so the star fill
  shows through underneath); the star isn't bordered, it's filled.
- **Padding:** ≥32px horizontal, 12px vertical.
- **End icon:** required (an arrow / arrow-like glyph). On hover, the icon
  translates right *and* the star rotates 72° clockwise.
- **Used for:** big, important, (ish-)irreversible actions — new post,
  submitting a rating, "Continue" in forms. The star is the cue that this is
  the climactic action of a flow; don't sprinkle it on minor buttons.

**Dark bg only** — special action isn't shown on light surfaces.

| | Normal | Hover | Pressed | Disabled |
| --- | --- | --- | --- | --- |
| Star + pill fill | `--color-brand-highlight` | `--color-brand-highlight` (star rotates 72° CW, end-icon shifts right) | white fill | `opacity: 0.5` over normal |
| Text | dark (`--color-set-1-bg`) | same | same | `opacity: 0.5` |

The 72° rotation = one fifth of a turn = one point of the star. Pressed locks
the star at the hover position with a subtle compression.

---

## 5. Forms and inputs

The Figma covers one field type so far.

### 5.1 Field pattern

- **Layout:** label on the left, input on the right (horizontal pair).
- **Label:** Label type token (Exo 2 16px regular).
- **Help icon:** a small `?` circle sits immediately after the label when the
  field has a tooltip / hint. Hover or focus reveals the hint.
- **Input:** rounded-corner box, set against set 1 background, with a thin
  muted border. Inherits its border color from the surrounding set's
  secondary-foreground.

When in doubt about a pattern that isn't in the Figma yet (radio groups,
selects, multi-line text), pick the choice most consistent with this one —
labels on the left, inputs filling the remaining row width, set-1 fills,
muted borders — and document the choice back into this section.

---

## 6. Spacing

Use `--space-*` from `_variables.scss` (`--space-xxxs` 4px →
`--space-xxxxl` 64px). The button paddings above (`16px`, `32px`, `12px`,
`3px`) don't all map cleanly to the scale — they're baked into the button
component styles rather than picked freshly per usage.
