# Intake: 1.0.0.rc1

> Intake taken on 2026-11-05.

## Request
Plan and spec 1.0.0.rc1, the release candidate for 1.0.0: out in early December, then about two
quiet weeks before 1.0.0 by 2026-12-31. It freezes the public API and the overhead budgets. From the
handoff's list (`.shipkit/state.md`, "Next step" 2):

- raise the floors to Rails 7.2 and Ruby 3.3, and CI from 20 rows to 9 (decision `0003`);
- a tested 0.x to 1.0 upgrade;
- how the version gets set: release-please has no `bump-minor-pre-major`, and `Release-As:` survives a
  squash, but check how it spells a prerelease first;
- the demo: its `~> 0.9` pin excludes 1.0.0, and its update workflow won't deploy a release candidate;
- the reversal clauses marked "Revisit at 1.0.0.rc1";
- re-read `docs/PUBLIC_API.md` and `docs/VERSIONING.md`, which are the freeze.

## Serves goal
Ship 1.0 — metric: v1.0.0 published on RubyGems with config and public API frozen; target: released;
by: 2026-12-31

## Conflicts found
- **Constraint in `.shipkit/product.md`:** "Rails 7.0–8.1, Ruby 3.2–4.0" (Constraints) and "release
  scenarios pass: fresh, upgrade and uninstall on SQLite, PostgreSQL and MySQL across Rails 7.0–8.1"
  (Metrics) contradict decision `0003`'s 1.0 floors. Not a conflict with the decision, which is the
  later and deliberate one, but product.md has to change in the same release. README.md:26 says the
  same, and calls RED "Beta".
- **Open spec `deploy-shape-benchmark`:** rc1 waits for it, because a code change for small boxes after
  rc1 restarts the quiet period. Its T18-T20 are still to build. Its first runs found two things rc1
  may have to answer: under `medium-throttled` (0.4 of a CPU) RED added +5.84 ms at p99 to the 1%
  failing mix, every pair positive; and with the database 1 ms away, capture with the installer's
  default async setting read 7.12 ms on x64 and 8.78 ms on arm64, against its 5 ms budget (runs
  42011156654 and 42011161060; capture, sync read 12.01 and 15.44 ms). The 5 ms was set against a
  database on the same machine.
- **Decision `0004`:** at 1.0, `async_adapter` and `llm_observability_content_capture` stay as warning
  no-ops, and are deleted only in 2.0. rc1 must not remove them.
- **Decision `0008`:** config and ENV names are frozen as they are. The 1.0 readiness blocker that asked
  to rename them (`.shipkit/research/1-0-readiness.md`, blocker 2) is answered by this record, not by
  rc1.
- **Open spec `keep-module-name`:** shipped by #349; it belongs in `_shipped/` when 0.18.1 is released
  (release PR #351). Not rc1's work, but it must not be left open into rc1.

## Answers
1. **The overhead budgets the freeze writes down.** Capture's 5 ms holds with the database on the same
   machine, but not 1 ms away (7.12 and 8.78 ms, above). Say what the budget assumes, change RED so it
   holds across a network, or raise it? And the health snapshot's 1 ms budget fails on two of
   the CPUs CI draws (Xeon 8573C and 8370C, 1.15 to 1.30 ms) and on every arm64 run (1.23 to 1.33 ms),
   while AMD x64 runs pass (0.47 to 0.86 ms). The gate's own clause counts failures on main until
   2026-11-30 (1 of 3 so far). Freeze 1 ms everywhere and change the gate, set the budget per
   architecture, or raise it? — *unanswered*
2. **Which 0.x releases the upgrade test starts from.** Blocker 7 says every 0.x minor; today's
   "Upgrade Path (published → this branch)" job starts from the latest release only. Every minor from
   0.1, the minors still in use (which would need download figures), or the last few? — *unanswered*
3. **The demo during the quiet weeks.** Run rc1 on the demo, so the release candidate is tried in
   production, which means widening its `~> 0.9` pin and teaching its update workflow about a
   prerelease, or keep the demo on 0.18.x until 1.0.0? — *unanswered*
4. **What of `deploy-shape-benchmark` must land before rc1.** T18 (the shape line) and T19-T20 (the
   compare tool and the research file) are planned before rc1; T21 (stacks and Ruby 4.0) was added
   on 2026-11-05 "if there's time". Is T21 needed before rc1, or after 1.0? — *unanswered*

## Assumptions made
- **The floors** follow decision `0003` exactly: the gemspec requires Rails >= 7.2 and Ruby >= 3.3, CI
  drops to 9 rows, and the Rails 7.0 code paths and the 1.x sqlite3 pin go. That also clears the two
  sqlite3 Dependabot alerts (`.shipkit/state.md`, "Two Dependabot alerts stay open until rc1").
- **The version** is set by a `Release-As:` trailer, which survives a squash merge
  (`.shipkit/state.md`, "Next step" 2). How release-please spells a Ruby prerelease, and whether
  RubyGems takes it as `1.0.0.rc1`, is checked in the spec, not assumed.
- **The docs pass** in the readiness file ("Strongly recommended") is rc1 work: the Beta label
  (README.md:26, docs/FAQ.md), ROADMAP's stale header, and the planned `severity_calculator`.
- **UPGRADING.md** gains a "0.x to 1.0" section (blocker 7); it has none today.
- **The reversal clause** "Remove the stats broadcast, keep the stats partial"
  (`_shipped/live-updates-hardening-0-17`) fires when a `v1.0.0*` tag exists, so rc1's tag fires it.
  The spec decides it before the tag, rather than after.
- **Feedback on the release candidate** is asked for in a GitHub issue or discussion, as the readiness
  file suggests ("ask early users to try it").

## Out of scope
- Anything decision `0002` moved to 1.1, the Full Context Error Report among them.
- Replacing Pagy (decision `0006`: pinned through 1.0, replaced in 1.x).
- RED Pro, the community translations (#156-#165), and the roadmap's open feature ideas.
- Releasing 0.18.1 (#351), which is its own release.
