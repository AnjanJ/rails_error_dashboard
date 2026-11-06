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

  # Below the floors nothing runs, so a branch for an older Rails or Ruby is
  # dead code, and a warning about one can never be seen.
  describe "code for versions below the floors" do
    let(:root) { File.expand_path("../../..", __dir__) }
    let(:ruby_floor) { Gem::Version.new("3.3") }
    let(:rails_floor) { Gem::Version.new("7.2") }

    def source_lines(globs)
      Dir.glob(globs, base: root).sort.flat_map do |path|
        File.readlines(File.join(root, path)).each_with_index.map { |line, index| [ "#{path}:#{index + 1}", line ] }
      end
    end

    def gem_lines
      source_lines([ "lib/**/*.{rb,erb,rake}", "app/**/*.{rb,erb}" ])
    end

    RAILS_VERSION_READ = /\b(?:Rails|ActionPack|ActiveRecord|ActiveSupport|ActiveJob|ActionView|Railties)\.(?:gem_)?version\b|Rails::VERSION/
    COMPARISON = /[<>]=?/
    VERSION_LITERAL = /"(\d+\.\d+(?:\.\d+)*)"/

    # A comparison against the floor or anything below it is always true or
    # always false from 1.0 on.
    def comparisons_at_or_below(read, floor)
      gem_lines.select do |_, line|
        line.match?(read) && line.match?(COMPARISON) &&
          line.scan(VERSION_LITERAL).flatten.any? { |version| Gem::Version.new(version) <= floor }
      end.map(&:first)
    end

    # release-1-0-rc1/REQ-3
    it "compares the Ruby version with nothing at or below 3.3" do
      expect(comparisons_at_or_below(/RUBY_VERSION/, ruby_floor)).to be_empty
    end

    # release-1-0-rc1/REQ-3
    it "compares the Rails version with nothing at or below 7.2" do
      expect(comparisons_at_or_below(RAILS_VERSION_READ, rails_floor)).to be_empty
    end

    # release-1-0-rc1/REQ-3. The 0.18 warnings for the floors, the Rails 7.0.10
    # request-capture warning, the Ruby 3.3 notice for swallowed exceptions, and
    # the shims for Rails 7.0's reporter, retry delay and enqueue result.
    it "holds none of the warnings or shims for older versions" do
      markers = [
        "RED 1.0 requires", "7.0.10", "swallowed_requires_ruby", "report_takes_source?",
        "POLYNOMIAL_BACKOFF", "respond_to?(:successfully_enqueued?)", "context[:middleware]"
      ]
      lines = gem_lines + source_lines([ "config/locales/*.yml" ])

      expect(lines.select { |_, line| markers.any? { |marker| line.include?(marker) } }.map(&:first)).to be_empty
    end

    # release-1-0-rc1/REQ-3
    it "keeps no Gemfile branch for Rails 7.0 or 7.1" do
      gemfile = File.read(File.join(root, "Gemfile"))

      aggregate_failures do
        expect(gemfile).not_to match(/start_with\?\("(?:~> )?7\.[01]/)
        expect(gemfile).not_to include('"~> 1.4"')
      end
    end
  end
end
