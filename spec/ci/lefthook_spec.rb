# frozen_string_literal: true

require "spec_helper"
require "yaml"

# Lefthook replaces {staged_files} with each staged file quoted on its own. A
# shell test written around it, `[ -n "{staged_files}" ]`, became
# `[ -n "a_spec.rb" "b_spec.rb" ]` with two specs staged: `[` failed, the `if`
# was false, and the hook passed without running anything. Lefthook isn't
# installed in CI, and running rspec from inside this suite would share its
# test database, so this holds the command to its plain shape. The behaviour
# was proven with lefthook itself: two staged specs, one failing, fail the hook.
RSpec.describe "lefthook pre-commit" do
  let(:config) { YAML.safe_load_file(File.expand_path("../../lefthook.yml", __dir__), aliases: false) }
  let(:rspec_changed) { config.dig("pre-commit", "commands", "rspec-changed") }

  it "passes the staged spec files straight to rspec (test-gaps-0-17/REQ-21)" do
    expect(rspec_changed["glob"]).to eq("*_spec.rb")
    expect(rspec_changed["run"].strip).to eq("bin/with-ruby bundle exec rspec {staged_files}")
  end
end
