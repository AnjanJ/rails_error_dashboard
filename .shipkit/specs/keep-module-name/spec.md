# Spec: Keep Ruby's own `name` on RED's classes

> Spec accepted at commit `37ceb3f` on fix/keep-module-name (2026-11-04).
> Status: open
> Paths: lib/rails_error_dashboard/services/ai_agent_classifier.rb,lib/rails_error_dashboard/queries/rack_attack_summary.rb,spec/lib/rails_error_dashboard/services/ai_agent_classifier_spec.rb,spec/lib/rails_error_dashboard/module_names_spec.rb

## Purpose
`AiAgentClassifier` defines `name(user_agent)` as a class method, which replaces Ruby's own `Class#name`
for that class, so asking it for its name with no argument raises `ArgumentError`. Code in a host app
that asks every loaded class for its name, as `ObjectSpace.each_object(Class).map(&:name)` does, crashes
once RED is loaded, and RED then records the crash as an error. RED must not break the host app.

## User stories
- As a Rails developer, I want tools that list my app's classes to keep working after I add RED, so that
  installing it costs me nothing elsewhere.

## Requirements (EARS)
- **REQ-1.** Every class and module RED defines shall answer `name`, called with no argument, with its own
  name.
- **REQ-2.** The AI agent classifier shall give the canonical name of a recognised agent, and nil for an
  unrecognised, browser or blank user agent, through a method other than `name`.

## Out of scope
- The plugins' `name` methods and `ManualErrorReporter::MockClass#name`. They're instance methods, so they
  don't replace a class's name.
- Any other change to how user agents are classified.

## Release steps
A `fix:` commit, so release-please proposes a patch. `AiAgentClassifier` is private under
`docs/PUBLIC_API.md` ("Classes and modules not named on this page"), so the rename needs no deprecation.
