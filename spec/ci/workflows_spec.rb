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
