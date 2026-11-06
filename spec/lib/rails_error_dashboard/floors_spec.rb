# frozen_string_literal: true

require "spec_helper"

# 1.0 requires Rails 7.2 and Ruby 3.3 (decision 0003). The floors rise only at
# a major, so these specs pin both the refused and the accepted side.
RSpec.describe "RED's version floors" do
  let(:gemspec) do
    Gem::Specification.load(File.expand_path("../../../rails_error_dashboard.gemspec", __dir__))
  end

  def assert_floor(requirement, refused:, accepted:)
    aggregate_failures do
      refused.each do |version|
        expect(requirement).not_to be_satisfied_by(Gem::Version.new(version)), "#{version} should be refused"
      end
      accepted.each do |version|
        expect(requirement).to be_satisfied_by(Gem::Version.new(version)), "#{version} should be allowed"
      end
    end
  end

  # release-1-0-rc1/REQ-1
  it "requires Ruby 3.3 or later" do
    assert_floor(
      gemspec.required_ruby_version,
      refused: %w[3.1.6 3.2.0 3.2.9],
      accepted: %w[3.3.0 3.3.9 3.4.12 4.0.0 4.0.9]
    )
  end

  # release-1-0-rc1/REQ-1
  it "requires Rails 7.2 or later" do
    rails = gemspec.runtime_dependencies.find { |dependency| dependency.name == "rails" }&.requirement

    expect(rails).not_to be_nil
    assert_floor(
      rails,
      refused: %w[7.0.0 7.0.10 7.1.0 7.1.5.2],
      accepted: %w[7.2.0 7.2.4 8.0.0 8.1.4 9.0.0]
    )
  end
end
