# Spec: Host-safety fixes for 0.18.0

> Spec accepted at commit `6b1dfab` on spec/0-18-0 (2026-10-29).
> Status: shipped in 0.18.0 (#337)
> Paths: lib/rails_error_dashboard/services/git_blame_reader.rb,lib/rails_error_dashboard/services/source_code_reader.rb,lib/rails_error_dashboard/helpers/user_model_detector.rb,spec/services/,spec/helpers/,spec/lib/

## Purpose
Two dashboard features can misbehave inside the host app's process:
- **Git blame** can leave a `git` process running after RED gives up on it.
- **View Source** can show a different file from the one a backtrace frame names.

1.0 promises no open host-safety bugs, so 0.18.0 fixes both.

## User stories
- As an operator, I want a slow `git blame` to end with no process left behind, so that the
  dashboard can't pile up processes in my app's process tree.
- As a developer reading a backtrace, I want View Source to show the frame's own file or nothing, so
  that I never debug the wrong code.

## Requirements (EARS)

### Git blame
- **REQ-1.** If `git blame` has not finished within `COMMAND_TIMEOUT`, then RED shall end that git
  process, reap it, and report "Git blame timeout" as it does today.
- **REQ-2.** When `git blame` finishes within `COMMAND_TIMEOUT`, RED shall return the same result
  as in 0.17.0.
- **REQ-3.** Git blame shall never raise into the dashboard request. Every failure gives `nil` and a
  message, as today.
- **REQ-4.** Ending a timed-out git process shall affect no other process, and shall not install or
  change a signal handler.

### View Source
- **REQ-5.** When a frame's path is absolute and outside `Rails.root`, View Source shall show the
  file at the same app-relative path under `Rails.root`, if that file exists. For example,
  `/old/release/app/models/user.rb` shows `Rails.root/app/models/user.rb`.
- **REQ-6.** If no such app-relative file exists, View Source shall show no source. It shall never
  show a file matched only by name.
- **REQ-7.** Every path View Source resolves shall still pass the existing safety checks: inside
  `Rails.root`, a source extension, no dot directory, no traversal, no sensitive pattern.

### The user count (added at the design gate, 2026-10-29)
- **REQ-8.** When RED counts the host app's users for user impact, it shall never interrupt the
  query from Ruby. A count that is too slow shall be ended by the database itself. The connection
  stays usable afterwards, and the count gives nil, as a failed count does today.

## Out of scope
- Changing `COMMAND_TIMEOUT` or the git blame output.
- New View Source behavior for paths inside `Rails.root`.
