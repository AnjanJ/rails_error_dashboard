# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Deprecation do
  let(:message) { "config.old_thing does nothing. Delete the line. It goes in 2.0." }

  describe ".warn" do
    it "writes one line, with the prefix, to the log (deprecations-0-18/REQ-1)" do
      allow(Rails.logger).to receive(:warn)

      described_class.warn(:old_thing, message)

      expect(Rails.logger).to have_received(:warn)
        .with("[Rails Error Dashboard] DEPRECATION: #{message}").once
    end

    it "reports a key once, however often it's used (deprecations-0-18/REQ-2)" do
      allow(Rails.logger).to receive(:warn)

      3.times { described_class.warn(:old_thing, message) }

      expect(Rails.logger).to have_received(:warn).once
    end

    it "reports two keys separately (deprecations-0-18/REQ-2)" do
      allow(Rails.logger).to receive(:warn)

      described_class.warn(:old_thing, message)
      described_class.warn(:other_thing, message)

      expect(Rails.logger).to have_received(:warn).twice
    end

    it "reports a key once across threads (deprecations-0-18/REQ-2)" do
      allow(Rails.logger).to receive(:warn)

      Array.new(8) { Thread.new { described_class.warn(:old_thing, message) } }.each(&:join)

      expect(Rails.logger).to have_received(:warn).once
    end

    it "also writes to standard error when asked, for a task run from cron (deprecations-0-18/REQ-1)" do
      expect { described_class.warn(:old_thing, message, stderr: true) }
        .to output("[Rails Error Dashboard] DEPRECATION: #{message}\n").to_stderr
    end

    it "stays off standard error otherwise (deprecations-0-18/REQ-1)" do
      expect { described_class.warn(:old_thing, message) }.not_to output.to_stderr
    end

    it "doesn't raise with no logger (deprecations-0-18/REQ-3)" do
      allow(Rails).to receive(:logger).and_return(nil)

      expect { described_class.warn(:old_thing, message) }.not_to raise_error
    end

    it "doesn't raise when the logger does, and still reaches standard error (deprecations-0-18/REQ-3)" do
      allow(Rails.logger).to receive(:warn).and_raise(IOError, "disk full")

      expect { described_class.warn(:old_thing, message, stderr: true) }.to output(/DEPRECATION/).to_stderr
    end

    it "doesn't raise when standard error is closed (deprecations-0-18/REQ-3)" do
      closed = StringIO.new.tap(&:close)
      original = $stderr
      $stderr = closed

      expect { described_class.warn(:old_thing, message, stderr: true) }.not_to raise_error
    ensure
      $stderr = original
    end

    it "doesn't raise when the app sets Active Support deprecations to raise (deprecations-0-18/REQ-3)" do
      deprecators = Rails.application.respond_to?(:deprecators) ? Rails.application.deprecators.each.to_a : [ ActiveSupport::Deprecation ]
      saved = deprecators.map(&:behavior)
      deprecators.each { |deprecator| deprecator.behavior = :raise }

      expect { described_class.warn(:old_thing, message) }.not_to raise_error
    ensure
      deprecators.zip(saved) { |deprecator, behavior| deprecator.behavior = behavior }
    end
  end
end
