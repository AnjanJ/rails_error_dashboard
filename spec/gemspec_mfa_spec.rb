# frozen_string_literal: true

require "spec_helper"

# A push of this gem needs its owner's MFA (hardening-1-0-rc2/REQ-14). The
# release workflow's trusted-publishing push isn't a user's key, so rubygems.org
# doesn't hold it to this (design.md, spike notes on REQ-14); a manual
# `gem push` is.
RSpec.describe "gemspec MFA requirement" do
  let(:spec) do
    Gem::Specification.load(File.expand_path("../rails_error_dashboard.gemspec", __dir__))
  end

  it "requires MFA to publish (hardening-1-0-rc2/REQ-14)" do
    expect(spec.metadata["rubygems_mfa_required"]).to eq("true")
  end
end
