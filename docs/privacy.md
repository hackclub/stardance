# Privacy requests (GDPR deletion and export)

Deletion and export requests are run from the Hack Club privacy hub at https://yeet.hackclub.com. The hub calls these endpoints once with `dry_run: true`. A human reviews the result, and after approval the hub calls again for real.

| Endpoint | Does |
| --- | --- |
| `POST /api/privacy/delete` | Erases the subject, or reports what would be erased on a dry run |
| `POST /api/privacy/export` | Reports what is held. Export delivery isn't specified yet, so it never changes anything, whatever `dry_run` says |

`Api::PrivacyController` inherits `ActionController::API`, so none of `ApplicationController`'s session, ban or tracking callbacks run.

## Authentication

Each call carries `Authorization: Bearer <token>`: an ES256 JWT signed by the hub. `Privacy::Token` verifies it with the `jwt` gem against the hub's JWKS (`https://yeet.hackclub.com/.well-known/jwks.json`). It checks:

- the signature against the key the token's `kid` names, with `alg: ES256` only, and `typ: JWT`
- `iss` is `hackclub-privacy` and `aud` is exactly `stardance` (`Privacy::Token::AUDIENCE`)
- `exp` and `iat` with 30 seconds of leeway, and a lifetime (`exp - iat`) of at most 300 seconds
- the shape of the claims, and that `action` matches the endpoint

Keys are cached for 5 minutes and refetched (at most every 30 seconds) when a token names an unknown `kid`, so key rotation on the hub needs no change here. Nothing needs configuring in production; `PRIVACY_JWKS_URL` only exists to point at a hub running locally.

The endpoints act only on the token claims (`subject.emails`, `subject.slack_id`, `subject.identity_id`, `dry_run`), never on the request body or query string. Each token's `jti` is accepted once: used IDs go in `privacy_token_uses` (`PrivacyTokenUse`) and are pruned after a day. They live in Postgres rather than `Rails.cache` because a cache that can't be written reports the same thing as a key that already exists, which would make every token look replayed.

Only the `request_id` and the outcome are logged. Never the token, emails, Slack IDs or identity IDs.

Responses:

- `200 {request_id, found, dry_run, deleted: {table: rows}, retained: [{type, count, reason}]}`. Once someone is erased, later calls answer `found: false`.
- `401 {error}` for a bad token, `400 action_mismatch`, `409 replayed`
- `409 manual_review_required` for staff accounts (any granted role) and people selling items in the shop, since other people depend on what they own. Staff handle those by hand.
- `503 jwks_unavailable` when the JWKS can't be fetched, and `503 dependency_unavailable` when file storage, search, Gorse or the Ahoy database fails during a real run. The hub retries both. A dependency failure releases the token's replay record after the erasure transaction rolls back, so the same unexpired token can be retried.

## Who is matched

Users whose `email`, `guest_email` or `hcb_email` matches one of the subject's emails (case-insensitively), whose `slack_id` matches, or whose Hack Club identity (`user_identities.uid` with provider `hack_club`) matches `identity_id`.

## How erasure works

Shop orders, ledger entries, payouts, card grants, warehouse packages, votes, reports and reviews all hold required foreign keys to `users`, and ledger entries are immutable by design. So the user row is kept as an **anonymous placeholder** rather than deleted, and everything personal is deleted or wiped. `Privacy::Eraser` does it all in one transaction, in SQL, so model callbacks (ledger guards, PaperTrail, search and Gorse syncs) don't fire. Because the users row is never deleted, no foreign key cascades, and the reported counts are exactly the rows removed.

### The account

The `users` row keeps its id, balances and non-personal settings. These are cleared:

- email, guest email, HCB email, first and last name, bio. The display name becomes `deleted-user-<id>`.
- Slack ID, IP address, user agent, geocoded location, timezone and age attestation
- API key, session token, referral refs, internal notes, ban reason, interests, regions and granted roles

Ledger entries whose `created_by` reads "Name (id)" are relabelled "Deleted user (id)".

With the identities gone and the email and Slack ID cleared, signing in again creates a new account, and the Airtable user sync skips the row because it has no email.

A real run records a `privacy_erasure` PaperTrail version on the placeholder account, holding only the hub's `request_id`, so it shows in the admin audit log.

### Deleted

- login identities, preferences, notification preferences, activity days, vote verdict, Hackatime project links, data exports and their ZIPs, the certificate (it holds their name), and the profile banner
- follows in both directions, project follows and skips, post views, reposts, memberships, daily rolls, Mihi activations, extension usage, Lookout sessions, vote assignments and vote telemetry (IP and user agent), streak activity, sticky streaks with no claimed reward, workshop RSVPs and attendance, mission memberships, review skips, Buku contributions, shop wishlists, messages to them, notifications to them, and Flipper actor gates
- comments and likes they made. Other people's like, comment, repost and view counts are recounted.
- their devlogs and git commits in any project, with the devlogs' likes, comments, edit history, attachments and notifications, and everyone's reposts of them. Git commits elsewhere authored with their email have the author cleared.
- their raffle sign-up (GitHub login, id and avatar), weekly claims and the referrals they made
- RSVPs, replies and games for any of their emails
- PaperTrail versions of everything above and of the account itself, except `balance_adjustment` entries, which are the ledger's audit trail and hold amounts and reasons. `whodunnit` is cleared wherever it was them.
- outside Postgres, on a real run only, before the transaction commits:
  - files in storage (Cloudflare R2 in production) for every deleted attachment, with their variants and previews
  - Ahoy visits and events, when the Ahoy database is configured. They're counted on a dry run.
  - their user, project, devlog and ship documents in the semantic search index, and its result cache
  - their user, project and post records in Gorse, when Gorse is enabled by configuration and the feature flag
  - cached balance and Hackatime API key entries

### Projects

A project where every current member is being erased is soft-deleted (`deleted_at`) and kept as a hidden placeholder, because ship events, votes, payouts and certification reviews reference it. Its title becomes "Deleted project". Its description, links, AI declaration and update description are cleared, the banner and demo video are purged, all of its devlogs and commits are deleted, ship event bodies, feedback videos and attachments are cleared, and other people's reposts of it are hidden. The same fields are stripped from its PaperTrail history.

In a project shared with people who stay, only their membership and their own devlogs and commits go. Their ship and fire event posts stay with `user_id` cleared. Member counts, devlog counts and durations are recounted.

A devlog that a YSWS review references can't be deleted, so it stays hidden, with its text, attachments and edit history removed.

### Closed

- Open shop orders (`pending`, `awaiting_verification`, `awaiting_verification_call`, `awaiting_periodical_fulfillment`, `on_hold`) are rejected with the reason "Cancelled: account deleted after a privacy request", so nothing ships to a deleted account. No refund is made, because the balance goes with the account.
- Pending reviewer payout requests and pending shop suggestions are rejected.

### Kept, and reported as `retained`

| Kept | Why |
| --- | --- |
| The account row | Anonymous placeholder so financial records stay linked |
| Shop orders, warehouse packages, card grants, hardware funding requests | Accounting, fulfilment, customs and HCB records |
| Ledger entries, payout lines, reviewer payout requests, show and tell attendances, mission prize redemptions, achievements, claimed sticky streaks | The ledger is immutable and must balance, and these are what it references |
| Votes cast and shop suggestion votes | Other people's rankings and payouts. Written vote reasons and their embeddings are removed. |
| Shop suggestions | Placeholders with text, link and image removed, because votes and stardust reference them |
| Reports filed, and fraud reviews about them | Fraud prevention |
| Reviews of their submissions, and review records they made | The record of staff decisions about people's work |
| Raffle wins and referrals credited to someone else | Draws reference the winner, and referrals count toward the person who referred them. GitHub details are removed. |
| Projects they solely owned, reviewed devlogs | Hidden placeholders, see above |
| Airtable copies | Not touched here; the hub's Airtable target deletes them |

Order and package addresses (`frozen_address`) stay on retained orders for fulfilment and customs.

## Dry runs

A dry run performs the real erasure inside a transaction, counts each table's deleted rows, and rolls back. Dry run and real run share one code path, so the reviewed numbers are the executed numbers. Nothing outside Postgres is touched on a dry run.

## Not covered

- Data the hub's own targets handle: Slack, Hack Club Auth, Hackatime, Loops, Airtable and Lapse.
- Copies held by HCB, Theseus, the Shipwrights dashboard and Lookout recordings.
- Error and analytics tooling: AppSignal, Skylight, `rails_performance`, `active_insights` and FullStory.
- Text already sent to OpenAI, OpenRouter or Anthropic.
- Arguments of jobs already in Solid Queue, which are cleared on the normal schedule.
- The `materialized_all_signups` view, which refreshes from the erased tables within a couple of minutes.

## Running it against a local hub

```sh
# .env
PRIVACY_JWKS_URL=http://host.docker.internal:44100/.well-known/jwks.json
```

In the hub, register a target with slug and audience `stardance` and base URL `http://127.0.0.1:3000`.
