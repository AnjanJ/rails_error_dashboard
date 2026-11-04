# Design: Keep Ruby's own `name` on RED's classes

## Approach
Rename the classifier's lookup and update its one caller. A spec that loads all of RED and asks every
class and module for its name keeps the next one from slipping in.

## Decision: Rename the lookup to `agent_name`, with no alias   (→ REQ-1, REQ-2)

**Context.** `AiAgentClassifier.name(user_agent)` replaces `Class#name`. Its one caller is
`Queries::RackAttackSummary`. The class is private (`docs/PUBLIC_API.md`, "What's private").

**Alternatives.**
1. Rename it to `agent_name(user_agent)`, and update the caller.
2. Keep `name`, make the argument optional, and call `super` when it's missing.
3. Keep `name(user_agent)` as a deprecated alias of `agent_name`.

**Case for renaming.** The class answers `name` like every other class, and nobody has to remember that
`name` means something else here. The class is private, so no deprecation is owed.

**Case against renaming.** Host code that called the private method breaks. Option 2 would keep it
working, but `name` would still mean two things. Option 3 keeps the bug until the alias goes.

**Decision.** We chose option 1.
**Falsifiability.** We would add `name(user_agent)` back as a deprecated alias if an issue reports a host
calling it.
**Fired-if.** manual
