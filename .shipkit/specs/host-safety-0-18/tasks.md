# Tasks: Host-safety fixes for 0.18.0

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `host-safety-0-18/REQ-N`. One commit per task, test and code together.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. The shell exports a stale
`RAILS_VERSION` that re-pins the lockfile. Run one rspec process at a time.

- [ ] **T1** Git blame ends and reaps a timed-out git, and only that git → REQ-1, REQ-2, REQ-3, REQ-4
  - Files: lib/rails_error_dashboard/services/git_blame_reader.rb, spec/services/git_blame_reader_spec.rb
  - Test: git_blame_reader_spec:
    - a fake `git` on `PATH` that sleeps past a stubbed `COMMAND_TIMEOUT` of 0.2 s → `nil`,
      error "Git blame timeout", and its pid is gone and reaped (`Process.kill(0, pid)` raises
      `Errno::ESRCH`);
    - the fake git starts a grandchild → the grandchild is gone too;
    - a sleeper the spec started itself survives;
    - `Signal.trap` is never called;
    - a real blame in a temp git repo returns the same hash as 0.17.0's parser gives for that
      output;
    - `Open3.popen3` raising → `nil` and a message, no raise
  - After: none
  - Done when: `R rspec spec/services/git_blame_reader_spec.rb` → 0 failures
- [ ] **T2** View Source maps an outside path to its app-relative file, or shows nothing → REQ-5, REQ-6, REQ-7
  - Files: lib/rails_error_dashboard/services/source_code_reader.rb, spec/services/source_code_reader_spec.rb
  - Test: source_code_reader_spec, with a temp `Rails.root`:
    - `/old/release/app/models/user.rb` → reads `Rails.root/app/models/user.rb`;
    - `/var/www/app/releases/OLD/app/models/user.rb` → the same file (the earlier `app` segment
      has no match);
    - a path whose only match is `Rails.root/user.rb` → `nil` with the not-available error;
    - a mapped path into `.git/` or to a `.yml` → refused by `validate_path!`
  - After: none
  - Done when: `R rspec spec/services/source_code_reader_spec.rb` → 0 failures
- [ ] **T3** The user count is bounded by the database, not by `Timeout` → REQ-8
  - Files: lib/rails_error_dashboard/helpers/user_model_detector.rb, spec/helpers/user_model_detector_spec.rb
  - Test: user_model_detector_spec:
    - `Timeout.timeout` is never called;
    - on SQLite, a plain count;
    - on PostgreSQL, against a view that sleeps past a stubbed limit → `nil`, nothing raised, and
      `SELECT 1` still works on the same connection;
    - on MySQL, the same through `MAX_EXECUTION_TIME`.

    The adapter examples are skipped unless the adapter matches.
  - After: none
  - Done when: `R rspec spec/helpers/user_model_detector_spec.rb` → 0 failures, and the same file
    is green on the PostgreSQL and MySQL `adapter-test` rows of the PR's CI run
