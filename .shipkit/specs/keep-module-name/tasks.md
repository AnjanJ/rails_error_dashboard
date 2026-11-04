# Tasks: Keep Ruby's own `name` on RED's classes

Test first: the cited tests fail before the change and pass after it. Every test cites
`keep-module-name/REQ-N`. Commands below stand for `env -u RAILS_VERSION mise exec ruby@3.4.5 -- bundle exec
rspec`.

- [ ] **T1** The classifier's lookup becomes `agent_name`, and no RED class or module replaces `name` → REQ-1, REQ-2
  - Files: lib/rails_error_dashboard/services/ai_agent_classifier.rb, lib/rails_error_dashboard/queries/rack_attack_summary.rb, spec/lib/rails_error_dashboard/services/ai_agent_classifier_spec.rb, spec/lib/rails_error_dashboard/module_names_spec.rb
  - Test: module_names_spec loads all of RED and asks every RED class and module for its name;
    ai_agent_classifier_spec calls `agent_name`
  - After: none
  - Done when: `rspec spec/lib/rails_error_dashboard/module_names_spec.rb spec/lib/rails_error_dashboard/services/ai_agent_classifier_spec.rb spec/lib/rails_error_dashboard/queries/rack_attack_summary_spec.rb` → 0 failures
