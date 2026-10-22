# frozen_string_literal: true

require "spec_helper"
require "yaml"

# Guards the least-privilege shape of the GitHub Actions workflows and of the
# bundle the release job installs (spec: .shipkit/specs/ci-least-privilege).
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

  # Values a PR author or a dispatcher chooses. Expanded inside `run:`, they
  # become part of the script itself; read from an env var, they stay data.
  UNTRUSTED_EXPRESSION = /\$\{\{[^}]*\b(?:github\.(?:head_ref|base_ref|event\.)|inputs\.)/

  # The workflows this spec holds to least privilege.
  def hardened_workflows
    %w[ci.yml test.yml smoke-test-demo.yml]
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

  describe "ci.yml and test.yml" do
    it "give every job read access to the repository and nothing else (ci-least-privilege/REQ-2)" do
      %w[ci.yml test.yml].each do |name|
        jobs(name).each_key do |job_id|
          expect(effective_permissions(name, job_id)).to eq({ "contents" => "read" }), "#{name}:#{job_id}"
        end
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
