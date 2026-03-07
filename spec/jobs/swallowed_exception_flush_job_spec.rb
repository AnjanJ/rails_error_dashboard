# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::SwallowedExceptionFlushJob, type: :job do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.detect_swallowed_exceptions = true
  end

  after do
    RailsErrorDashboard.configuration.detect_swallowed_exceptions = false
    RailsErrorDashboard::SwallowedException.delete_all
  end

  describe "#perform" do
    context "with snapshot arguments (TracePoint dispatch mode)" do
      it "delegates to FlushSwallowedExceptions command" do
        raise_counts = { "RuntimeError|app/foo.rb:10" => 5 }
        rescue_counts = { "RuntimeError|app/foo.rb:10->app/foo.rb:15" => 4 }

        expect(RailsErrorDashboard::Commands::FlushSwallowedExceptions).to receive(:call).with(
          raise_counts: raise_counts,
          rescue_counts: rescue_counts
        )

        described_class.perform_now(raise_counts, rescue_counts)
      end

      it "creates database records" do
        raise_counts = { "RuntimeError|app/foo.rb:10" => 3 }
        rescue_counts = {}

        expect {
          described_class.perform_now(raise_counts, rescue_counts)
        }.to change(RailsErrorDashboard::SwallowedException, :count).by(1)
      end
    end

    context "without arguments (cron safety net mode)" do
      it "calls SwallowedExceptionTracker.flush!" do
        expect(RailsErrorDashboard::Services::SwallowedExceptionTracker).to receive(:flush!)

        described_class.perform_now
      end
    end

    context "with only raise_counts (rescue_counts nil)" do
      it "falls through to cron mode (calls flush!)" do
        expect(RailsErrorDashboard::Services::SwallowedExceptionTracker).to receive(:flush!)

        described_class.perform_now({ "RuntimeError|app/foo.rb:10" => 1 }, nil)
      end
    end

    context "when feature is disabled" do
      before do
        RailsErrorDashboard.configuration.detect_swallowed_exceptions = false
      end

      it "returns early without processing" do
        expect(RailsErrorDashboard::Commands::FlushSwallowedExceptions).not_to receive(:call)
        expect(RailsErrorDashboard::Services::SwallowedExceptionTracker).not_to receive(:flush!)

        described_class.perform_now({ "RuntimeError|app/foo.rb:10" => 1 }, {})
      end
    end

    context "when command raises an error" do
      it "lets the error propagate (ActiveJob retry handles it)" do
        allow(RailsErrorDashboard::Commands::FlushSwallowedExceptions).to receive(:call).and_raise(
          ActiveRecord::ConnectionNotEstablished
        )

        expect {
          described_class.perform_now({ "RuntimeError|app/foo.rb:10" => 1 }, {})
        }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end
    end
  end
end
