# Intake: live-updates hardening for 0.17.0

> Intake taken on 2026-10-23.

## Request
Harden live updates for 0.17.0, for hosts that turn them on (`config.enable_live_updates`, off by
default since #308):
1. The error list's stream subscriptions are signed once and never expire. RED's stream names are
   constants, so the signed values are the same on every page load, forever. A subscription made
   with one keeps receiving new error rows after the viewer's dashboard access ends.
2. The stats broadcast computes `Queries::DashboardStats` and replaces `#dashboard_stats`, an
   element no built-in page renders. It is the most expensive part of a broadcast, and it updates
   nothing.

## Serves goal
"Ship 1.0 — metric: v1.0.0 published on RubyGems with config and public API frozen". 0.17.0 is the
release before 1.0.0.rc1 (`.shipkit/research/1-0-readiness.md`).

## Conflicts found
- **Non-goal "No removing a shipped free feature"** (`.shipkit/product.md`, line 24).
  - Making subscriptions expire means RED's broadcasts can no longer reach a subscription made
    through `Turbo::StreamsChannel`, because every token that channel accepts for RED's current
    names never expires. A custom index view (docs/CUSTOMIZATION.md, "Custom Views") that
    subscribes with `turbo_stream_from "error_list"` stops receiving updates. It must render RED's
    helper instead, which a view override can, because it runs inside RED's controller. This
    changes how the feature is used without removing it, so it gets an upgrade note.
  - Stopping the stats broadcast removes the live stats stream that the guide says only a custom
    view could use. *Question 1: the user chose to stop it entirely.*
- **Paramount non-goal: no process-wide side effects in the host process** (line 20). RED must not
  patch `Turbo::StreamsChannel` or the host's `ApplicationCable::Connection`. The fix adds a RED
  channel of its own.
- **Paramount non-goal: request-path features switchable by config** (line 19). Already met by
  `enable_live_updates`. Nothing new runs while it is off.
- **Open spec `live-updates-client`** (#308, marked open). This spec changes the stream contract
  that spec's guide documents (names, channel, the stats stream). Its decisions stay: the gate
  inside `ErrorBroadcaster.available?` and off by default. Its out-of-scope list deferred
  "reducing what an enabled broadcast costs"; this spec takes that up for the stats part.
- **Decisions:** `.shipkit/decisions/0001` is not touched.

## Answers
1. The stats broadcast: stop it entirely, stop it by default behind a new option, or give the index
   a `#dashboard_stats` region? **Stop it entirely** (user, 2026-10-23). Live updates carry rows
   only. No new setting before the 1.0 config freeze. The 1.0 overhead benchmark decides whether a
   live stats region is worth its cost.

## Assumptions made
- **Decided on 2026-10-22, not re-asked:** this ships in 0.17.0, and live updates stay off by
  default.
- **No new settings.** The subscription lifetime is a constant with a stated reason (the 1.0 config
  freeze).
- **Expiry needs a refresh path.** A page left open must keep its live updates without a reload, so
  it renews its subscriptions through a dashboard-authenticated request before they expire. A
  viewer who has lost access can't renew, so their live updates end within one lifetime.
- **RED keeps building turbo-stream messages with turbo-rails' broadcast methods.** Live updates
  still need turbo-rails and Action Cable in the host, as today.
- **Action Cable stays optional.** A host without Action Cable boots and eager-loads exactly as
  today; RED's channel is loaded only when Action Cable is (the pattern at `engine.rb:211`).
- **Rows carry what they carry today.** The row partial is unchanged.

## Out of scope
- Authenticating the host's `ApplicationCable::Connection`. It is the host's code; the guide keeps
  telling hosts what it needs to admit.
- Turning live updates on by default (revisit for 1.0), and live updates on the demo app (a
  separate repository and PR).
- A polling fallback, and Turbo Drive for the dashboard.
- A live stats region on any page.
