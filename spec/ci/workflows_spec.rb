# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "open3"

# Guards the least-privilege shape of the GitHub Actions workflows and of the
# bundle the release job installs (spec: .shipkit/specs/_shipped/ci-least-privilege).
#
# WHY THIS EXISTS: GitHub evaluates these files only when they run, and a
# permission mistake in them shows up as nothing at all. A job silently keeps
# a permission it never needed, or a whole workflow fails at startup and stops
# opening release PRs (the smoke-test wiring did exactly that once). These
# examples read the files as data, so a change that widens a job's token or
# drops a guard fails here, on every PR, instead of on the next release.
RSpec.describe "GitHub Actions workflows" do
  def repo_root
    File.expand_path("../..", __dir__)
  end

  # Psych reads the `on:` key as the boolean true (YAML 1.1); nothing below
  # needs the triggers except where it says so.
  def workflow(name)
    YAML.safe_load_file(File.join(repo_root, ".github/workflows", name), aliases: false)
  end

  def jobs(name)
    workflow(name).fetch("jobs")
  end

  # The permissions a job's token gets: its own block if it has one, else the
  # workflow's. nil means neither declares any, so the repository default applies.
  def effective_permissions(name, job_id)
    wf = workflow(name)
    job = wf.fetch("jobs").fetch(job_id)
    job.key?("permissions") ? job["permissions"] : wf["permissions"]
  end

  # [job_id, step] for every step of every job. A job that calls a reusable
  # workflow has no steps of its own.
  def steps(name)
    jobs(name).flat_map { |job_id, job| Array(job["steps"]).map { |step| [ job_id, step ] } }
  end

  # A repository whose HEAD is one commit past origin/main, adding `path`.
  # Git's hook variables are unset: this spec also runs inside the
  # pre-commit hook, where they point at the real repository.
  def repo_changing(path)
    dir = Dir.mktmpdir("red_changes_gate")
    git = lambda do |*args|
      out, status = Open3.capture2e(git_env, "git", "-c", "user.name=spec", "-c", "user.email=spec@example.com",
        "-c", "commit.gpgsign=false", *args, chdir: dir)
      raise "git #{args.join(' ')} failed: #{out}" unless status.success?
    end
    git.call("init", "-q", "-b", "main")
    git.call("commit", "-q", "--allow-empty", "-m", "base")
    git.call("update-ref", "refs/remotes/origin/main", "HEAD")
    FileUtils.mkdir_p(File.join(dir, File.dirname(path)))
    File.write(File.join(dir, path), "change\n")
    git.call("add", path)
    git.call("commit", "-q", "-m", "change")
    dir
  end

  def git_env
    { "GIT_DIR" => nil, "GIT_WORK_TREE" => nil, "GIT_INDEX_FILE" => nil }
  end

  # Runs a step of ci.yml's changes job the way a runner would and returns what
  # it wrote to $GITHUB_OUTPUT.
  def changes_step_output(step_id, changed:, **env)
    step = jobs("ci.yml").fetch("changes").fetch("steps").find { |candidate| candidate["id"] == step_id }
    dir = repo_changing(changed)
    output_file = File.join(dir, "github_output")
    env = git_env.merge(env.transform_keys(&:to_s), "BASE_REF" => "main", "GITHUB_OUTPUT" => output_file)
    log, status = Open3.capture2e(env, "bash", "-eo", "pipefail", "-c", step.fetch("run"), chdir: dir)
    expect(status).to be_success, log
    File.read(output_file).strip
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  # Values a PR author or a dispatcher chooses. Expanded inside `run:`, they
  # become part of the script itself; read from an env var, they stay data.
  UNTRUSTED_EXPRESSION = /\$\{\{[^}]*\b(?:github\.(?:head_ref|base_ref|event\.)|inputs\.)/

  # The workflows this spec holds to least privilege.
  def hardened_workflows
    %w[ci.yml test.yml smoke-test-demo.yml release.yml]
  end

  describe "every hardened workflow" do
    it "declares the token permissions of every job in the file itself (ci-least-privilege/REQ-1)" do
      undeclared = hardened_workflows.flat_map do |name|
        jobs(name).keys.select { |job_id| effective_permissions(name, job_id).nil? }.map { |job_id| "#{name}:#{job_id}" }
      end

      expect(undeclared).to eq([])
    end

    it "persists no credentials from any checkout (ci-least-privilege/REQ-11)" do
      persisting = hardened_workflows.flat_map do |name|
        steps(name)
          .select { |_job_id, step| step["uses"].to_s.start_with?("actions/checkout@") }
          .reject { |_job_id, step| step.dig("with", "persist-credentials") == false }
          .map { |job_id, _step| "#{name}:#{job_id}" }
      end

      expect(persisting).to eq([])
    end

    it "expands no ref, event or input value inside a run script (ci-least-privilege/REQ-12)" do
      expanding = hardened_workflows.flat_map do |name|
        steps(name)
          .select { |_job_id, step| step["run"].to_s.match?(UNTRUSTED_EXPRESSION) }
          .map { |job_id, step| "#{name}:#{job_id}:#{step['name']}" }
      end

      expect(expanding).to eq([])
    end
  end

  describe "every workflow" do
    # A tag can be moved to other code; a commit SHA can't. Dependabot's
    # github-actions updates keep the pins current, and the audit job's zizmor
    # checks each pin against the tag named in its comment.
    it "pins every action it uses to a full commit SHA (test-gaps-0-17/REQ-19)" do
      names = Dir[File.join(repo_root, ".github/workflows/*.yml")].map { |path| File.basename(path) }.sort
      unpinned = names.flat_map do |name|
        references = steps(name).map { |_job_id, step| step["uses"] }.compact + jobs(name).values.map { |job| job["uses"] }.compact
        references.reject { |ref| ref.start_with?("./") || ref.match?(/@\h{40}\z/) }.map { |ref| "#{name}: #{ref}" }
      end

      expect(names).to include("ci.yml", "test.yml", "pages.yml", "release.yml", "smoke-test-demo.yml")
      expect(unpinned).to eq([])
    end
  end

  describe "ci.yml and test.yml" do
    it "give every job read access to the repository and nothing else (ci-least-privilege/REQ-2)" do
      %w[ci.yml test.yml].each do |name|
        jobs(name).each_key do |job_id|
          expect(effective_permissions(name, job_id)).to eq({ "contents" => "read" }), "#{name}:#{job_id}"
        end
      end
    end
  end

  # The upgrade-path test runs only when it can catch something. A job skipped
  # by its `if` shows as Skipped and counts as passing for a required check; a
  # job that skips all its own steps shows as a pass that ran nothing.
  describe "ci.yml: the upgrade gate" do
    let(:ci_jobs) { jobs("ci.yml") }

    def decide(head_ref:, changed:)
      changes_step_output("decide", changed: changed, "HEAD_REF" => head_ref)
    end

    it "skips the upgrade job at the job level, on the changes job's answer (test-gaps-0-17/REQ-14)" do
      upgrade = ci_jobs.fetch("upgrade")

      expect(Array(upgrade["needs"])).to eq([ "changes" ])
      expect(upgrade["if"]).to eq("needs.changes.outputs.upgrade == 'true'")
      expect(ci_jobs.dig("changes", "outputs", "upgrade")).to eq("${{ steps.decide.outputs.run }}")
      expect(upgrade.fetch("steps").map { |step| step["if"] }.compact).to eq([])
    end

    it "says no for a pull request that changes no migration (test-gaps-0-17/REQ-14)" do
      expect(decide(head_ref: "fix/something", changed: "lib/something.rb")).to eq("run=false")
    end

    it "says yes for a pull request that changes a migration (test-gaps-0-17/REQ-15)" do
      expect(decide(head_ref: "fix/something", changed: "db/migrate/20990101000000_x.rb")).to eq("run=true")
    end

    it "says yes for a release pull request (test-gaps-0-17/REQ-15)" do
      expect(decide(head_ref: "release-please--branches--main--components--rails_error_dashboard",
        changed: "CHANGELOG.md")).to eq("run=true")
    end
  end

  # Fails CI when RED goes over a budget. It runs on every push to main, and on
  # the pull requests that change what it measures.
  describe "ci.yml: the benchmark job" do
    let(:benchmark) { jobs("ci.yml").fetch("benchmark") }

    def run_step
      benchmark.fetch("steps").find { |step| step["run"].to_s.include?("bin/benchmark") }
    end

    it "reads the repository and nothing else, with its actions pinned (overhead-benchmark/REQ-8)" do
      references = benchmark.fetch("steps").filter_map { |step| step["uses"] }

      expect(effective_permissions("ci.yml", "benchmark")).to eq({ "contents" => "read" })
      expect(references).to include(a_string_starting_with("actions/checkout@"), a_string_starting_with("ruby/setup-ruby@"))
      expect(references).to all(match(/@\h{40}\z/))
    end

    it "runs on every push to main, and on a pull request when the changes job says so (overhead-benchmark/REQ-8)" do
      expect(workflow("ci.yml").fetch(true).dig("push", "branches")).to eq([ "main" ])
      expect(Array(benchmark["needs"])).to eq([ "changes" ])
      expect(benchmark["if"]).to eq("github.event_name == 'push' || needs.changes.outputs.capture == 'true'")
      expect(jobs("ci.yml").dig("changes", "outputs", "capture")).to eq("${{ steps.capture.outputs.run }}")
    end

    it "stays on one pinned row, so its numbers compare between runs (overhead-benchmark/REQ-8)" do
      expect(benchmark.dig("env", "RAILS_VERSION")).to eq("8.1")
      expect(benchmark.fetch("steps").find { |step| step["uses"].to_s.start_with?("ruby/setup-ruby@") }.dig("with", "ruby-version")).to eq("3.4")
    end

    it "writes the table to the job summary and fails the job on a breach (overhead-benchmark/REQ-9)" do
      expect(run_step["run"]).to include('bundle exec bin/benchmark --summary "$GITHUB_STEP_SUMMARY"')
      expect(run_step["run"]).not_to include("--smoke")
      expect(benchmark).not_to have_key("continue-on-error")
      expect(run_step).not_to have_key("continue-on-error")
    end

    %w[
      lib/rails_error_dashboard/middleware/error_catcher.rb
      lib/rails_error_dashboard/subscribers/breadcrumb_subscriber.rb
      lib/rails_error_dashboard/commands/log_error.rb
      lib/rails_error_dashboard/services/storm_protection/gate.rb
      lib/rails_error_dashboard/error_reporter.rb
      bin/benchmark
      benchmark/scenarios.rb
      .github/workflows/ci.yml
    ].each do |path|
      it "says yes for a pull request that changes #{path} (overhead-benchmark/REQ-8)" do
        expect(changes_step_output("capture", changed: path)).to eq("run=true")
      end
    end

    %w[
      lib/rails_error_dashboard/queries/errors_list.rb
      app/views/rails_error_dashboard/errors/index.html.erb
      spec/benchmark/timer_spec.rb
      README.md
    ].each do |path|
      it "says no for a pull request that changes only #{path} (overhead-benchmark/REQ-8)" do
        expect(changes_step_output("capture", changed: path)).to eq("run=false")
      end
    end
  end

  # A required check. Each tool must be able to fail it: nothing may continue
  # on error, and each runs with the options that make it strict.
  describe "ci.yml: the audit job" do
    let(:audit) { jobs("ci.yml").fetch("audit") }

    def audit_step(command)
      audit.fetch("steps").find { |step| step["run"].to_s.include?(command) }
    end

    it "reports as `audit`, with the read-only token, and never continues on error" do
      expect(audit).not_to have_key("name")
      expect(effective_permissions("ci.yml", "audit")).to eq({ "contents" => "read" })
      expect([ audit, *audit.fetch("steps") ].map { |entry| entry["continue-on-error"] }.compact).to eq([])
    end

    it "checks the bundle against an advisory database fetched in the same run (test-gaps-0-17/REQ-16)" do
      expect(audit_step("bundle-audit")["run"]).to include("bundle-audit check --update")
    end

    it "runs actionlint from a release checked against a pinned SHA-256 (test-gaps-0-17/REQ-17)" do
      script = audit_step("actionlint")["run"]

      expect(script).to include("sha256sum --check", "./actionlint")
      expect(audit.dig("env", "ACTIONLINT_SHA256")).to match(/\A\h{64}\z/)
    end

    it "runs zizmor online on every workflow at low severity and up (test-gaps-0-17/REQ-18)" do
      step = audit_step("zizmor")

      expect(step["run"]).to include("--min-severity low", ".github/workflows/")
      expect(step["run"]).not_to include("--offline")
      expect(step.dig("env", "GH_TOKEN")).to eq("${{ github.token }}")
      expect(audit.dig("env", "ZIZMOR_VERSION")).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe "release.yml" do
    let(:release_jobs) { jobs("release.yml") }

    def job_steps(job_id)
      release_jobs.fetch(job_id).fetch("steps")
    end

    def runs?(step, command)
      step["run"].to_s.include?(command)
    end

    def version_check_step
      job_steps("test").find { |step| step.dig("env", "INPUT_VERSION") }
    end

    # Runs the version check the way a runner would (bash -eo pipefail), from
    # the repo root, with the Ruby running this spec first on PATH.
    def run_version_check(input_version)
      env = {
        "INPUT_VERSION" => input_version,
        "PATH" => "#{RbConfig::CONFIG['bindir']}#{File::PATH_SEPARATOR}#{ENV['PATH']}"
      }
      Bundler.with_unbundled_env do
        Open3.capture2e(env, "bash", "-eo", "pipefail", "-c", version_check_step.fetch("run"), chdir: repo_root)
      end
    end

    it "grants id-token: write to the publish job alone, and nothing at the workflow level (ci-least-privilege/REQ-3)" do
      expect(workflow("release.yml")["permissions"]).to eq({})

      with_id_token = release_jobs.keys.select { |job_id| effective_permissions("release.yml", job_id)&.dig("id-token") == "write" }
      expect(with_id_token).to eq([ "publish" ])
      expect(effective_permissions("release.yml", "publish")).to eq({ "contents" => "write", "id-token" => "write" })
    end

    it "runs the test suite and RuboCop only in the read-only test job (ci-least-privilege/REQ-4)" do
      testing = release_jobs.keys.select do |job_id|
        Array(release_jobs[job_id]["steps"]).any? { |step| runs?(step, "bundle exec rspec") || runs?(step, "bundle exec rubocop") }
      end

      expect(testing).to eq([ "test" ])
      expect(effective_permissions("release.yml", "test")).to eq({ "contents" => "read" })
    end

    it "gives release-please only what it needs to open release PRs and releases (ci-least-privilege/REQ-5)" do
      expect(effective_permissions("release.yml", "release")).to eq({ "contents" => "write", "pull-requests" => "write" })
    end

    it "installs the publish job's bundle without the development and test groups (ci-least-privilege/REQ-6)" do
      groups = release_jobs.fetch("publish").fetch("env").fetch("BUNDLE_WITHOUT").split(":")

      expect(groups).to include("development", "test")
    end

    it "restores no Bundler cache in any job, so every gem is installed fresh (ci-least-privilege/REQ-6)" do
      cached = steps("release.yml").select { |_job_id, step| step.dig("with", "bundler-cache") == true }

      expect(cached).to eq([])
    end

    it "publishes only after the test job has passed in the same run (ci-least-privilege/REQ-8)" do
      test_job = release_jobs.fetch("test")
      publish = release_jobs.fetch("publish")

      expect(Array(test_job["needs"])).to eq([ "release" ])
      # On a dispatch, `release` is skipped; without !cancelled() the skip
      # would propagate and silently skip test and publish too.
      expect(test_job["if"]).to include("!cancelled()", "workflow_dispatch", "needs.release.outputs.release_created")
      expect(Array(publish["needs"])).to eq([ "test" ])
      expect(publish["if"]).to include("!cancelled()", "needs.test.result == 'success'")
    end

    it "publishes from the rubygems environment (ci-least-privilege/REQ-9)" do
      environment = release_jobs.fetch("publish").fetch("environment")

      expect(environment.is_a?(Hash) ? environment["name"] : environment).to eq("rubygems")
    end

    it "pins every action it uses to a full commit SHA (ci-least-privilege/REQ-13)" do
      references = steps("release.yml").map { |_job_id, step| step["uses"] }.compact +
        release_jobs.values.map { |job| job["uses"] }.compact
      unpinned = references.reject { |ref| ref.start_with?("./") || ref.match?(/@\h{40}\z/) }

      expect(references).not_to be_empty
      expect(unpinned).to eq([])
    end

    it "runs the demo smoke test after a publish from main, with read and issues access (ci-least-privilege/REQ-14)" do
      smoke = release_jobs.fetch("smoke-test")

      expect(smoke["uses"]).to eq("./.github/workflows/smoke-test-demo.yml")
      expect(Array(smoke["needs"])).to eq([ "publish" ])
      expect(smoke["if"]).to include("github.event_name == 'push'", "needs.publish.result == 'success'")
      expect(effective_permissions("release.yml", "smoke-test")).to eq({ "contents" => "read", "issues" => "write" })
    end

    it "passes the smoke test only the two demo secrets (ci-least-privilege/REQ-17)" do
      expect(release_jobs.fetch("smoke-test")["secrets"]).to eq(
        "DEMO_USER" => "${{ secrets.DEMO_USER }}",
        "DEMO_PASSWORD" => "${{ secrets.DEMO_PASSWORD }}"
      )
    end

    describe "the republish version check (ci-least-privilege/REQ-15)" do
      it "runs on dispatch only, before the test suite" do
        check_index = job_steps("test").index(version_check_step)
        rspec_index = job_steps("test").index { |step| runs?(step, "bundle exec rspec") }

        expect(version_check_step["if"]).to include("workflow_dispatch")
        expect(version_check_step.dig("env", "INPUT_VERSION")).to eq("${{ inputs.version }}")
        expect(check_index).to be < rspec_index
      end

      it "passes when the input matches version.rb" do
        output, status = run_version_check(RailsErrorDashboard::VERSION)

        expect(status).to be_success, output
      end

      it "fails when the input differs from version.rb" do
        output, status = run_version_check("0.0.0-not-this-version")

        expect(status).not_to be_success
        expect(output).to include("does not match")
      end
    end
  end

  describe "smoke-test-demo.yml" do
    # release.yml passes these two by name (no `secrets: inherit`), and a
    # caller can only pass secrets the called workflow declares.
    it "declares the two demo secrets it reads as optional workflow_call secrets (ci-least-privilege/REQ-17)" do
      secrets = workflow("smoke-test-demo.yml").fetch(true).fetch("workflow_call").fetch("secrets")

      expect(secrets.keys).to contain_exactly("DEMO_USER", "DEMO_PASSWORD")
      expect(secrets.values.map { |secret| secret["required"] }).to all(be(false))
    end
  end

  describe "Gemfile" do
    # The release job installs the bundle with the development and test groups
    # left out. Anything in the default group is installed, and built, there.
    it "keeps only the gem, rails and the json constraint in the default group (ci-least-privilege/REQ-7)" do
      dsl = Bundler::Dsl.new
      dsl.eval_gemfile(File.join(repo_root, "Gemfile"))
      default_group = dsl.dependencies.select { |dep| dep.groups.include?(:default) }.map(&:name)

      expect(default_group - %w[rails_error_dashboard rails json]).to eq([])
    end
  end
end
