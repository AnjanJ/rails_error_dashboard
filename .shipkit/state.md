# Handoff

> Written 2026-10-21 at commit `d34cee7` on docs/1-0-readiness.

## In flight
- 1.0 readiness: analysis written, not yet a spec. Five decisions are open: `.shipkit/research/1-0-readiness.md`.
- This note and that analysis are committed on branch `docs/1-0-readiness`.

## Done this session
- Local main synced. The gem went 852f5c5 → d34cee7; the demo went e7c4363 → ae45d95 and runs 0.16.1.
- `.shipkit/product.md` written and merged (#305). Goals by 2026-12-31: ship 1.0, a reproducible overhead benchmark, 100k downloads and 200 stars. The host-app rules are marked paramount.
- 1.0 deep dive: public-surface inventory, open-items audit, and research on Rails/Ruby EOL dates and comparable gems.

## Next step
Read the local `tasks/handoff-2026-10-21.md` first, then answer the five decisions in `.shipkit/research/1-0-readiness.md` and run `/shipkit:spec 1-0-readiness`.

## Open questions
- Is 1.0 stability-only, with the roadmap's "v1.0 anchor" feature moved to 1.1?
- Minimum Rails and Ruby at 1.0: 7.2 and 3.3 is recommended.
- `async_adapter` and `llm_observability_content_capture`: remove or implement?
- Webhook v1: a clean change in 0.17, or both formats for a while? Pagy: widen or replace?
- Branch cleanup (about 35 local branches, 3 worktrees) still awaits approval.

## Do not forget
- SSH fetch and push fail: use HTTPS URLs. Merge with `gh api ... /merge`. Main needs lint plus 27 green checks.
- Prefix bundle and commit with `env -u RAILS_VERSION mise exec ruby@3.4.5 --`. Doc-only commits use `LEFTHOOK_EXCLUDE=chaos-tests`.
- Re-check agent findings before acting: one was false (`on_critical_error` does fire).
- `tasks/` is gitignored and local to this machine.
