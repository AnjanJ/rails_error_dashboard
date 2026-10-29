# 0004: Retire `async_adapter` and `llm_observability_content_capture` as warning no-ops

- **Date:** 2026-10-29. Status: accepted (the maintainer confirmed on 2026-10-29; drafted from
  `.shipkit/research/1-0-readiness.md`, re-checked on `main` at ccc28e9).

## Context

Two config options do nothing, and 1.0 would freeze them as public API.

- `async_adapter` (`configuration.rb:128`, default `:sidekiq` at `:392`) is only validated
  (`:680-683`) and shown on Settings (`settings.html.erb:40-41`). Async capture runs on the host's
  Active Job adapter, whatever this option says. The installer writes
  `config.async_adapter = :async` uncommented whenever async logging is chosen
  (`install/templates/initializer.rb:194`), and the installer chooses async logging by default
  since v0.6.3. So most installed apps set it.
- `llm_observability_content_capture` (`configuration.rb:265`, default false at `:536`) is read
  nowhere. The docs call it "Reserved for future use" (`docs/LLM_OBSERVABILITY.md:208`).

## Alternatives

1. Implement both: `async_adapter` picks the job backend for RED's jobs, and content capture
   records LLM prompts and completions when turned on.
2. Delete both at 1.0, after a deprecation in 0.18.
3. Deprecate both in 0.18, and from 1.0 keep each as a setter that warns once and does nothing.
   Delete them in 2.0.

## Case for 3

Neither option should exist. Making `async_adapter` choose a backend would mean RED overriding
the host's Active Job adapter for its own jobs, the kind of acting on another gem's territory
that decision 0001 rules out. Capturing prompt text puts user PII into error reports, against
RED's privacy stance and the "no APM yet" non-goal. If either is ever wanted, adding an option
in a 1.x minor is not a breaking change. Option 2's deletion would raise `NoMethodError` while
the host app's initializer loads, crashing boot for every app the installer set up with async
logging. That breaks the paramount host-app rule over a line RED itself wrote. A setter that
warns and ignores the value gets the same result with no crash.

## Case against 3

Two dead names stay in the code and on Settings through all of 1.x, plus the warning code and its
specs. Users who never read boot logs keep the line in their initializer for years. And the
1.0 API is cleaner on paper with option 2.

## Decision

3. In 0.18, both setters log one deprecation warning when given a value; the installer stops
writing `async_adapter`; Settings and the docs drop both; UPGRADING tells users to delete the
lines. At 1.0 the setters stay as warning no-ops, and the getters return nil. They are deleted
in 2.0.

**I would reverse this if** RED gains an async path that doesn't run on Active Job (then a
backend option means something again), or if three or more users ask for opt-in prompt capture.
**Fired-if.** manual
