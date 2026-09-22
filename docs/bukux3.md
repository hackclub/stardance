# Buku x3

Enable the `bukux3` Flipper flag globally to start the event, or enable it for
individual actors while testing. The feature is registered but disabled by
default. Disabling the flag hides the reveal without clearing dismissals.

In local development, the **test buku animation** button at the top of the page
replays the scene regardless of login, role, or flag state. Previews never write
a dismissal. The button and preview bypass are unavailable in production.

Each signed-in account has a deterministic, server-side 50% chance of being a
Buku Buku. `BukuX3::Assignment.buku?(user)` is the source of truth. It uses an
HMAC of the account ID and the application's secret key, so refreshes and
different devices give the same result. This is an independent 50/50 draw,
not a quota guaranteeing exactly half of a small group. Changing the secret
key or assignment salt changes the cohorts; keep both stable during the event.

Only Buku Buku accounts see the reveal. Normal accounts continue as usual.
The reveal waits until onboarding and any existing welcome/bukux2 intro are
finished, then appears on the next application page. Completion, Skip, Escape,
or navigating away records `bukux3_role_reveal` through the existing authenticated
dismissal endpoint. Once recorded, the account does not see it again. A failed
dismissal request can cause a replay on a later visit.

The original supplied APNG has eleven 100ms frames, with repeated final frames.
`shh-animated.webp` preserves the 1.1-second sequence at 1100×825, combines the
identical final frames, and plays once. `shh.webp` is the reduced-motion still.
The scene darkens the page and brings up the shushing artwork,
then reveals “you are a buku buku.” It closes after 5.8 seconds; reduced-motion
users get a static scene that stays until dismissed. A native modal dialog
contains keyboard focus and makes the underlying page inert.

Visual reference: the [Among Us shushing intro](https://among-us.fandom.com/wiki/Red),
using the supplied Stardance artwork and brand colors. No Among Us artwork or
audio is bundled.

Tests: `bin/rails test test/services/buku_x3 test/components/buku_x3_reveal_component_test.rb`.
Use a dedicated test database when running these commands in Docker.
