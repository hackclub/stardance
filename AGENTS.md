# Stardance Agent Instructions

## Environment

Check with the user if the local setup uses docker. If so run anything using `docker compose run --service-ports web COMMAND`.
You can't run in an interactive docker shell but you can execute one-off commands.

## Build & Test Commands

- **Run all tests**: `bin/rails test`
- **Lint & Fix**: `bin/lint`
- **Start dev server**: `bin/dev`
- **Database setup**: `bin/rails db:prepare`

## Architecture & Structure

- **Framework**: Ruby on Rails 8.1.
- **Database**: PostgreSQL with `solid_queue` (jobs).
- **Caching**: Redis (`redis_cache_store`) in production, `memory_store` in development.
- **Key Gems**:
  - `pundit` (Authorization)
  - `aasm` (State Machines)
  - `paper_trail` (Versioning)
  - `flipper` (Feature Flags)
  - `view_component` (UI Components)
- **Deployment**: Coolify (Docker-based), not Kamal.

## Code Style & Conventions

- **Style**: Follows `rubocop-rails-omakase` defaults.
- **Testing**: Use **Minitest** (default Rails testing). Do not use RSpec.
  - Fixtures are used for test data (`test/fixtures/`).
- **Frontend**:
  - Use `esbuild` for JS and `dartsass-rails` for CSS.
  - Place controllers in `app/javascript/controllers`.
- **Security**:
  - Use `lockbox` and `blind_index` for encrypted fields.
  - Ensure `pundit` policies are applied in controllers.

When making changes/creations towards admin sides of the codebase there needs to be proper papertrail code and audit logging which should be accessible.

DB migrations should always ask for user confirmation.

When making code changes that require migrations, always use `bin/rails generate migration` instead of manually creating migration files. Manually creating migrations can cause issues when the AI generates improper migration syntax or timestamps.

Bias for rails generators (ie. rails g model/migration) when first creating a file.

We want maintainable code! Please use proper code formatting and naming conventions, also please use css classes instead of raw `style=` attributes, if possible use already existing components or partials.

When coding please do not produce unnecessary code or any dead code, if u make dead code please make sure to remove it and clean it up!

Please use BEM SCSS styling when writing SCSS: https://getbem.com/introduction/

## Codebase heritage: Flavortown → Stardance

This codebase is being re-used from a previous Hack Club program called
**Flavortown**, which used a brown-wood, food-themed visual identity. The goal
is to turn it into a new program called **Stardance**, which is space-themed and
uses the new branding guidelines (see the theming section below and
[docs/branding.md](docs/branding.md)).

When implementing something:

- **Reuse if clean.** If a previous Flavortown component / partial / helper
  already does what you need and is well-written, prefer reusing it.
- **Otherwise re-implement and purge.** If the old code is messy or tightly
  coupled to the food/wood theme, re-implement it cleanly and delete the old
  system rather than layering on top of it. Don't leave dead Flavortown code
  behind.
- **Always use Stardance branding, never Flavortown.** Anything you implement
  must use the new Stardance branding — even when reusing a component that
  already exists, update it so it uses the new space-themed palette, type, and
  patterns. Never carry the old brown-wood / food styling forward.

## Stardance themeing

The full visual identity spec — palette, type scale, container sets, button
states, form patterns — lives in [docs/branding.md](docs/branding.md). Read it
before doing visual work; it's the source of truth and is mirrored from the
Figma design system page.

Design tokens (background, brand palette, spacing, fonts, font sizes) are defined as CSS variables in [app/assets/stylesheets/config/_variables.scss](app/assets/stylesheets/config/_variables.scss). Reference them via `var(--token-name)` rather than inlining hex / rem values.

Background: `#08061E` (`--color-space-bg` / set on `<html>` in `landing/_base.scss`).

Brand palette — use the `--color-brand-*` variables in code:

- `#81FFFF` — `--color-brand-mint`
- `#EBB7FF` — `--color-brand-lilac`
- `#95DBFF` — `--color-brand-blue`
- `#FF8D9D` — `--color-brand-salmon`
- `#FFE564` — `--color-brand-yellow`
- `#FFD598` — `--color-brand-peach`
- `#FFF8D5` — `--color-brand-cream`
- `#FFFCF4` — `--color-brand-off-white`
- `#FFB07A` — `--color-brand-orange` — **reserved**: admin / manageable-by-viewer marker only (2px dashed border, see [docs/branding.md §1.5](docs/branding.md)). Don't use it for general accents.

When trying to choose a color, please try to choose from one of the colors above by default. If not, you can fall back to similar pastel colors. Try to avoid colors that are too saturated / deep. See [docs/branding.md](docs/branding.md) for the four "set" container surfaces, highlight tones, and which accent applies where.

For the font, use Exo 2 for most body text and title text, with emphasis being in Playfair Display italics. The full type scale (Title, Title 2, Heading, Small heading, Body, Label) with sizes and weights is documented in [docs/branding.md](docs/branding.md).