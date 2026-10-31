# Intake: host-safety fixes for 0.18.0

> Intake taken on 2026-10-29.

## Request
Fix the two open host-safety bugs from the 1.0 readiness research (blocker 6, "no open host-safety
bugs"), re-checked at `6b1dfab`:
1. **Git blame:** `services/git_blame_reader.rb:97-99` wraps `Open3.capture3` in `Timeout.timeout`.
   On timeout the Ruby thread gives up, and the child `git` process keeps running in the host app's
   process tree.
2. **View Source:** `services/source_code_reader.rb:106-108` cuts an absolute path outside
   `Rails.root` down to its basename and joins it to `Rails.root`. So
   `/old/release/app/models/user.rb` is looked up as `Rails.root/user.rb`, and a frame can show a
   different file that has the same name.

## Serves goal
"Ship 1.0" (`.shipkit/product.md`). The product's paramount constraint: no process-wide side effects
in the host process, and nothing that blocks the host beyond budget.

## Conflicts found
- **Paramount: no process-wide side effects.** The git fix must kill only the child it started and
  reap it. It must not install a signal handler (rule 9) or touch any other process.
- **Both run on dashboard requests, not on the capture path.** Their budgets are the dashboard's:
  the existing `COMMAND_TIMEOUT`, and a View Source request that never raises.
- **Open specs and decisions:** none touch these files. The capture-source spec (shipped) recorded
  a falsifiability clause on `SourceCodeReader.new` call sites, and this fix doesn't add one.

## Answers
1. **Add the user-count `Timeout` to this spec** (2026-10-29, at the design gate).
   `helpers/user_model_detector.rb:99` wraps `model_class.count` in `Timeout.timeout(5)`, on the
   Settings and user-impact pages (cached five minutes, `configuration.rb:1257-1275`).
   Interrupting an Active Record query from Ruby can leave its connection mid-protocol in the
   host's pool. This became REQ-8.

## Assumptions made
- **The timeout value stays as it is** (`COMMAND_TIMEOUT`).
- **No mapping, no source.** When a path outside `Rails.root` has no app-relative match, View Source
  shows its existing "source not available" state.

## Out of scope
- Other `Timeout.timeout` uses in the gem. The design step lists them, and any found in the host
  process go in the bug file, not this spec.
