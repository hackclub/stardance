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
