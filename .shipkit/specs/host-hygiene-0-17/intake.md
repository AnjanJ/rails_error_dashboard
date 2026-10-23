# Intake: host and dependency hygiene for 0.17.0

> Intake taken on 2026-10-23.

## Request
Three host-hygiene fixes for 0.17.0, all decided on 2026-10-22:
1. In an API-only host, RED adds cookie, session and flash middleware to the host's whole stack, so
   every API endpoint gets cookie sessions. Scope them to the dashboard, and add an API-only chaos
   app so it stays fixed.
2. The layout loads nine CDN files with no Subresource Integrity. Pin each with an integrity hash,
   after moving the two files jsDelivr generates (and could re-minify) to files that ship in their
   packages.
3. The gemspec admits concurrent-ruby versions with three known CVEs, and its comment says RED uses
   no ReadWriteLock, which is false. Raise the floor to 1.3.7 and correct the comment.

## Serves goal
"Ship 1.0 — metric: v1.0.0 published on RubyGems with config and public API frozen". 0.17.0 is the
release before 1.0.0.rc1 (`.shipkit/research/1-0-readiness.md`).

## Conflicts found
- **Paramount non-goal: no process-wide side effects in the host process** (`.shipkit/product.md`,
  line 20). Today's API-host middleware breaks it, and `engine.rb` line 37 claims the opposite
  ("ONLY for Error Dashboard routes"). The fix restores the rule. It is a behaviour change for an
  API host that came to rely on app-wide sessions, which then get Rails' `DisabledSessionError`
  again. Decided 2026-10-22: no escape-hatch flag, a release-notes line instead.
- **Non-goal "No removing a shipped free feature"** (line 24). Not hit. App-wide sessions in API
  hosts were never a feature; the comment says they were meant for the dashboard only.
- **Constraint "Adds nothing to the host app's asset pipeline"** (line 37). Not hit: the files stay
  on the CDN, now with integrity hashes. Vendoring them was the alternative, and was not chosen.
- **Open spec `live-updates-client`** (#308, marked open): its decision "Load the client from
  jsDelivr, the unminified npm file, with SRI" is the pattern this spec extends to the other nine
  files. Not a conflict.
- **Decisions:** `.shipkit/decisions/0001` is not touched.

## Answers
None asked. The maintainer took these decisions on 2026-10-22:
- API-only hosts: engine-scoped middleware, no escape-hatch flag, a release-notes line, and an
  `--api` chaos app.
- CDN files: SRI on all 9 files, the 2 jsDelivr-generated ones switched first. Google Fonts stays
  unhashed.
- concurrent-ruby: floor `"~> 1.3", ">= 1.3.7"` plus a corrected comment.

## Assumptions made
- **The API chaos app runs in `bin/pre-release-test all`**, so every chaos run (lefthook and PRs)
  checks it, not only `release_audit`. It costs about a minute per run.
- **The dashboard in an API host must keep working end to end:** login, a CSRF-protected POST, the
  flash after it, and the language picker. Those are the session's users, so the chaos app
  exercises them, not just page loads.
- **A host that already runs its own session middleware keeps its session in the dashboard.** An
  `authenticate_with` lambda may read it, so RED must not replace it with one of its own.
- **Integrity hashes are constants that specs pin**, with vendored copies of the scripts specs
  execute (#308's pattern). A failed hash blocks only that file; the dashboard degrades the way it
  does when the CDN is unreachable.
- **No new settings** (the 1.0 config freeze).
- **Docs:** `CLAUDE.md`'s CDN list is wrong (it names three libraries; the layout loads seven
  scripts and four stylesheets), so it is fixed here too.

## Out of scope
- Vendoring or self-hosting the CDN files.
- A Content Security Policy for the dashboard (the guide already says what a strict host CSP needs).
- Fonts and other files that CSS loads (SRI covers only the tag's own file).
- The live-updates client (pinned in #308).
