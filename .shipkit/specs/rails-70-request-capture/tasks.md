# Tasks: Rails 7.0 request capture

Every new example cites `rails-70-request-capture/REQ-N` in its name. CI's 7.0 rows install
Rails 7.0.10, so the examples stub `ActionPack.gem_version` instead of depending on the row.
Commands run in the normal checkout as
`env -u RAILS_VERSION mise exec ruby@3.4.5 -- bundle exec rspec …`.

- [x] **T1** Warn at boot on Rails older than 7.0.10 → REQ-1, REQ-2
  - Files: lib/rails_error_dashboard/configuration.rb, spec/lib/rails_error_dashboard/configuration_validation_spec.rb
  - Test: configuration_validation_spec "rails-70-request-capture/REQ-1 warns once on Rails older than 7.0.10" (actionpack stubbed to 7.0.8.7) and "…/REQ-2 does not warn on Rails 7.0.10 or later" (stubbed to 7.0.10, and the real version).
  - After: none
  - Done when: `bundle exec rspec spec/lib/rails_error_dashboard/configuration_validation_spec.rb` → 0 failures; the REQ-1 example fails before the change.
- [x] **T2** Correct the docs → REQ-3
  - Files: README.md, docs/QUICKSTART.md, _getting_started/quickstart.md, docs/TROUBLESHOOTING.md, _reference/troubleshooting.md
  - Test: none, REQ-3 is prose (`[untested]`). `spec/docs/links_spec.rb` stays green.
  - After: none
  - Done when: `bundle exec rspec spec/docs/links_spec.rb --example "Documentation links"` → 0 failures; the full suite → 0 failures, RuboCop clean.

## After the gate
- A real Rails 7.0.10 production app via a new 7.0 row in the local
  `tasks/docs-audit/release_scenarios.sh` (`json < 3`): a raising route records once and a 404
  records nothing. The result goes in the 0.16.1 scenarios record.
- The 0.16.1 release notes correct the 0.16.0 known-limitation note.
