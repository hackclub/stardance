# Buku x3

## Admin metrics and visual safety control

**the jim takeover** (`/admin/jim_takeover`), linked beside Super Mega Dashboard
on the admin home page, shows saved role discoveries and the last 14 days of daily
active shippers as a stacked bar chart: purple buku bukus and yellow beans.
Days use **America/New_York** time (including daylight
saving changes). A shipper counts once per team per day when they have a positive
approved event contribution. Grouping uses the original ship date, so late
approvals and corrections update historical days. Unapproved, zeroed, and
pre-event ships do not count. These totals refresh with the normal contribution
reconciliation and an admin page reload.

Full admins can set **visual intensity** from 0–200% on that page: 0 disables
the visual effect, 100 is normal, and 200 doubles the current effect, capped at
full disintegration. Team hours, the damage score, cutoff, and assignments are
unchanged. New pages receive the saved value immediately; existing live pages
pick it up on their next minute poll. Intro/reveal protection and cursor repair
still apply.

The setting defaults to 100%, persists on `BukuX3::Event`, and every change is
recorded by PaperTrail with the acting admin. The control links to filtered audit
history. Apply both visual-intensity migrations before deploying the new code.

## Launch and local previews

Enable the `bukux3` Flipper flag globally to run the event. It has no scheduled
start date or end date and no longer checks the old 5,000-hour goal or `bukux2`.
The flag is the launch switch. Accounting preserves any existing saved cutoff;
otherwise the first refresh with the global flag enabled captures the current
time. Only ships submitted **strictly after** that cutoff count for bukux3.

The feature is registered but disabled by default. Actor-specific enablement
can preview the existing shared state, but the accounting job requires global
enablement. Disabling bukux3 hides the reveal and restores the page without
clearing the cutoff, contributions, or dismissals. On re-enable, eligible ships
submitted during the pause are reconciled too.

Development-only `?buku_preview=buku` / `?buku_preview=bean` URLs show a
labeled home-panel preview without changing roles or dismissals. The parameter
is ignored outside development. A real reveal refreshes the home strip after
its dismissal is saved, without needing a manual page reload.

For local real-accounting tests, enable `bukux3`, then run
`BukuX3::RefreshJob.perform_now`. No fake 5,000-hour total is required.
The old `bukux2_preview_complete` flag only affects the old rocket bar.

Disintegration uses normal staged decay with the 145px cursor repair pocket
enabled. Event test buttons and simulator panels are no longer rendered, even
in development or when the legacy `blackhole` flag is enabled. Live damage is
controlled by `bukux3`; admins can adjust visual strength on **the jim takeover**.

Each signed-in account has a deterministic, server-side 50% chance of being a
Buku Buku. `BukuX3::Assignment.buku?(user)` is the source of truth. It uses an
HMAC of the account ID and the application's secret key, so refreshes and
different devices give the same result. This is an independent 50/50 draw,
not a quota guaranteeing exactly half of a small group. Changing the secret
key or assignment salt changes the cohorts; keep both stable during the event.

When `bukux3` is enabled, every onboarded account first sees Vega explain the
bukus, the beans, and their opposing shipped-hour effects in a visual novel.
The welcome tour still takes priority. This chapter replaces the obsolete
bukux2 repair intro for late arrivals. Finishing or skipping the explanation
saves `bukux3_intro`, then fetches the role reveal on the same page. The server
does not render or compute that user's reveal role before the explanation is
completed; the endpoint independently checks the flag and intro completion.
If the connection fails, the next load resumes the intro or pending reveal.

Both cohorts receive the same shushing artwork and animation, followed by
“you are a buku buku” or “you are a bean.” The supplied purple and yellow
indicators appear above the respective role names. After reveal completion,
home replaces the rocket bar with a private role reminder and live tug-of-war
meter. The buku is on the left and the bean on the right; the marker's position
is `100 - damage%`, so buku hours pull left and bean hours pull right. Existing
role icons are temporary endpoint artwork pending the holding-character drawings.
The ship form shows a compact reminder of how approved hours affect
the ship. These use the signed-in viewer, never the project or profile owner,
and are not added to public posts or profiles.
Completion, Skip, Escape,
or navigating away records `bukux3_role_reveal` through the existing authenticated
dismissal endpoint. Once recorded, the account does not see it again. A failed
dismissal request can cause a replay on a later visit.

The original supplied APNG has eleven 100ms frames, with repeated final frames.
`shh-animated.webp` preserves the 1.1-second sequence at 1100×825, combines the
identical final frames, and plays once. `shh.webp` is the reduced-motion still.
The scene darkens the page and brings up the shushing artwork,
then reveals “you are a buku buku.” Both reveals close after 5.8 seconds; reduced-motion
users get a static scene that stays until dismissed. A native modal dialog
contains keyboard focus and makes the underlying page inert.

Visual reference: the [Among Us shushing intro](https://among-us.fandom.com/wiki/Red),
using the supplied Stardance artwork and brand colors. No Among Us artwork or
audio is bundled.

## Accounting and operation

- `BukuX3::Unlock` preserves an existing `buku_x3_events.unlocked_at`, or captures
  first observation of global `bukux3` enablement. The recurring refresh checks
  every minute. Run `BukuX3::RefreshJob.perform_now` at launch if a precise
  immediate cutoff is needed; there is no inferred historical 5,000-hour date.
  UI availability depends on the flag, not on whether the accounting job ran.
- Once saved, the cutoff never moves, even if fraud corrections bring the rocket
  total below 5,000. Bukux2 keeps its existing campaign window; bukux3 has no date
  window and continues indefinitely after the cutoff.
- `BukuX3::RefreshJob` runs every minute in production. It snapshots completed
  YSWS reviews using the same approved-minute floor, banned-user exclusion, and
  net fraud deductions as rocket repair. Pending, rejected, and misfiled reviews
  do not contribute. Approved-time edits and later bans are reconciled, too.
- Each contribution saves its role, ship timestamp, review, user, and current net
  minutes. Unique database constraints and a locked event row make retries safe.
  Both event and contribution changes are versioned with PaperTrail.
- Replay contributions in ship-time order (review ID breaks ties), starting at
  **25% destruction** (75,000 equivalent damage minutes). This baseline is not
  a real contribution and does not appear in hours reports. Buku minutes add
  damage; bean minutes repair it. Every
  **50 hours changes intensity by 1 percentage point**. Clamp after each ship to
  0–100%, so repairs at zero and damage at 100% are not banked. There is no terminal
  state: a normal ship can repair a fully destroyed site. Late approvals or fraud
  corrections recompute that deterministic history.
- On deployment of the starting-balance change, run `BukuX3::RefreshJob.perform_now`
  (or wait for the scheduled refresh) to rebase existing event snapshots.
  Cutoffs, contribution records, and personal approved hours are preserved;
  only the derived damage balance changes. No schema migration is needed.
- Browsers receive the shared percentage and aggregate approved hours for each
  team, never individual roles. Team totals exclude the starting damage and
  include all counted contributions even when damage clamps at an endpoint.
  Open pages
  keep all disintegration off until that account completes the intro and role
  reveal. Replaying either local scene also suspends damage until it closes.
  Open pages poll once a minute; normal reloads also read current state. The live event has
  no manual slider or simulator controls.
- Local `bin/dev` does not run the production scheduler. Run
  `bin/rails runner 'BukuX3::RefreshJob.perform_now'` after test shipments when
  testing locally. Do not manually enable or seed this event in production to
  test the animation; use a local development account.

The 50/50 assignment is per account, not per hour: unequal productivity can move
the balance toward either end even with equally sized teams.

## SQL reporting

These read-only queries can be run later. Stored timestamps are UTC. Classifying
ships uses submission time, not approval time: an old ship reviewed after the
cutoff still belongs to the earlier phase. Before a cutoff exists, these queries
intentionally return no phase report. `before_bukux3` includes older campaigns,
so additionally filter by the existing rocket campaign window when reporting
only bukux2 participants.

```sql
-- Who submitted ships on either side of the recorded transition?
SELECT p.user_id,
       CASE WHEN se.created_at > e.unlocked_at
            THEN 'bukux3' ELSE 'before_bukux3' END AS phase,
       COUNT(*) AS ships
FROM post_ship_events se
JOIN posts p ON p.postable_type = 'Post::ShipEvent' AND p.postable_id = se.id
CROSS JOIN buku_x3_events e
WHERE e.key = 'bukux3' AND e.unlocked_at IS NOT NULL
GROUP BY p.user_id, phase
ORDER BY p.user_id, phase;

-- Approved bukux3 hours by user and saved role, as of the latest refresh.
-- These are participation totals, not the clamped visual balance.
SELECT c.user_id, c.buku, COUNT(*) FILTER (WHERE c.minutes > 0) AS counted_ships,
       ROUND(SUM(c.minutes) / 60.0, 2) AS approved_hours
FROM buku_x3_contributions c
JOIN buku_x3_events e ON e.id = c.event_id
WHERE e.key = 'bukux3'
GROUP BY c.user_id, c.buku
ORDER BY c.user_id;
```

Tests: `bin/rails test test/services/buku_x3 test/services/rocket_progress_test.rb test/components/buku_x3_reveal_component_test.rb test/components/buku_x3_intro_component_test.rb test/controllers/buku_x3`.
Use a dedicated test database when running these commands in Docker.
