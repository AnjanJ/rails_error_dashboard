# frozen_string_literal: true

require "rails_helper"
require "open3"
require "rbconfig"
require "tmpdir"

# The engine wires its drains once, at boot, and only for the features that
# are on: an at_exit hook that writes out what is still buffered when the
# process stops, and an executor to_complete hook that drains at the end of
# each request or job. The entry points are specced elsewhere; this checks the
# WIRING, which only a boot can show. The dummy app enables none of these
# features, and re-running the engine's boot block in this process would
# subscribe everything twice, so a child process boots the dummy app with all
# five on, swaps each drain for a recorder that prints a line, runs one
# executor unit of work, and exits normally, so the real at_exit hooks fire.
RSpec.describe "engine drains in a booted app" do
  child_script = <<~'RUBY'
    $stdout.sync = true
    crash_dir = ARGV.fetch(0)

    require File.expand_path("spec/dummy/config/application", Dir.pwd)
    # The dummy app never calls Bundler.require, and the engine wires
    # Rack::Attack tracking only when the constant exists.
    require "rack/attack"

    # After the dummy app's own initializer (it turns storm protection off),
    # and before the engine's boot-time crash hook reads the flag.
    Dummy::Application.initializer "engine_drains_spec.enable_features",
      after: :load_config_initializers, before: "rails_error_dashboard.crash_capture" do
      RailsErrorDashboard.configure do |config|
        config.enable_rack_attack_tracking = true
        config.enable_missing_translation_tracking = true
        config.enable_storm_protection = true
        config.enable_crash_capture = true
        config.crash_capture_path = crash_dir # boot imports from here: keep it empty
        config.detect_swallowed_exceptions = true
      end
    end

    Rails.application.initialize!

    services = RailsErrorDashboard::Services
    {
      [ services::RackAttackTracker, :flush_all_threads! ] => "exit rack_attack",
      [ services::RackAttackTracker, :flush_if_due! ] => "complete rack_attack",
      [ services::MissingTranslationTracker, :flush_all_threads! ] => "exit missing_translations",
      [ services::MissingTranslationTracker, :flush_if_due! ] => "complete missing_translations",
      [ services::StormProtection::Gate, :drain! ] => "exit storm",
      [ services::StormProtection::Gate, :flush_if_due! ] => "complete storm",
      [ services::CrashCapture, :capture! ] => "exit crash",
      [ services::SwallowedExceptionTracker, :flush_all_threads! ] => "exit swallowed",
      [ services::SwallowedExceptionTracker, :flush_if_due! ] => "complete swallowed"
    }.each do |(target, method), line|
      target.define_singleton_method(method) { |*| puts line }
    end

    puts "booted"
    Rails.application.executor.wrap { }
    puts "exiting"
  RUBY

  before(:context) do
    Dir.mktmpdir("red_drains_spec") do |crash_dir|
      root = File.expand_path("../../..", __dir__)
      out, err, status = Open3.capture3(RbConfig.ruby, "-e", child_script, crash_dir, chdir: root)
      @child_lines = out.lines.map(&:chomp)
      @child_error = "exit #{status.exitstatus}\n#{err}"
      @child_ok = status.success?
    end
  end

  # Swallowed-exception detection needs Ruby 3.3. On older Rubies the tracker
  # never enables (no exit drain), though its end-of-work hook is still wired
  # before config validation turns the flag off, so its lines are left out of
  # both comparisons there.
  def comparable(lines)
    RUBY_VERSION >= "3.3" ? lines : lines.reject { |line| line.end_with?(" swallowed") }
  end

  def lines_between(first, last)
    start = @child_lines.index(first)
    stop = @child_lines.index(last)
    expect([ start, stop ]).to all(be_an(Integer)), "child output: #{@child_lines.inspect}\n#{@child_error}"
    @child_lines[(start + 1)...stop]
  end

  it "boots and exits cleanly" do
    expect(@child_ok).to be(true), @child_error
  end

  it "runs each feature's end-of-work drain when an executor unit of work completes (test-gaps-0-17/REQ-4)" do
    expected = [ "complete rack_attack", "complete missing_translations", "complete storm", "complete swallowed" ]

    expect(comparable(lines_between("booted", "exiting"))).to match_array(comparable(expected))
  end

  it "runs each feature's exit drain when the process exits (test-gaps-0-17/REQ-3)" do
    exit_lines = @child_lines.drop((@child_lines.index("exiting") || @child_lines.size) + 1)
    expected = [ "exit rack_attack", "exit missing_translations", "exit storm", "exit crash", "exit swallowed" ]

    expect(comparable(exit_lines)).to match_array(comparable(expected)), "child output: #{@child_lines.inspect}\n#{@child_error}"
  end

  # at_exit hooks run last-registered first. The crash hook is registered by
  # an initializer, before after_initialize registers the others, so it runs
  # last; the fallback registration in after_initialize would run it first.
  it "registers the crash hook at boot, before the after_initialize drains (test-gaps-0-17/REQ-3)" do
    expect(@child_lines.last).to eq("exit crash"), "child output: #{@child_lines.inspect}\n#{@child_error}"
  end
end
