# frozen_string_literal: true

require "spec_helper"

# Runtime dependency bounds that were chosen on purpose, so they don't drift
# back by accident.
RSpec.describe "gemspec runtime dependencies" do
  let(:spec) do
    Gem::Specification.load(File.expand_path("../rails_error_dashboard.gemspec", __dir__))
  end

  def requirement(name)
    spec.runtime_dependencies.find { |dependency| dependency.name == name }&.requirement
  end

  # host-hygiene-0-17/REQ-8. 1.3.6 and earlier carry three CVEs fixed in 1.3.7.
  # None is reachable through RED's own code, but a floor keeps new bundles,
  # and the host's other gems, off them. No ceiling: an upper bound in an
  # engine only makes bundle conflicts.
  it "requires concurrent-ruby 1.3.7 or later, within 1.x" do
    concurrent = requirement("concurrent-ruby")

    aggregate_failures do
      %w[1.3.6 1.2.0 2.0.0].each do |version|
        expect(concurrent).not_to be_satisfied_by(Gem::Version.new(version)), "#{version} should be refused"
      end
      %w[1.3.7 1.3.8 1.4.0].each do |version|
        expect(concurrent).to be_satisfied_by(Gem::Version.new(version)), "#{version} should be allowed"
      end
    end
  end
end
