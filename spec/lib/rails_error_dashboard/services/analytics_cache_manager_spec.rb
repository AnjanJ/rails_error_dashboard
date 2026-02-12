# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::AnalyticsCacheManager do
  describe ".clear" do
    context "when cache supports delete_matched" do
      it "clears all analytics cache patterns" do
        cache = instance_double(ActiveSupport::Cache::MemoryStore)
        allow(Rails).to receive(:cache).and_return(cache)
        allow(cache).to receive(:respond_to?).with(:delete_matched).and_return(true)
        allow(cache).to receive(:delete_matched)

        described_class.clear

        expect(cache).to have_received(:delete_matched).with("dashboard_stats/*")
        expect(cache).to have_received(:delete_matched).with("analytics_stats/*")
        expect(cache).to have_received(:delete_matched).with("platform_comparison/*")
      end
    end

    context "when cache does not support delete_matched" do
      it "logs info and does not raise" do
        cache = instance_double(ActiveSupport::Cache::NullStore)
        allow(Rails).to receive(:cache).and_return(cache)
        allow(cache).to receive(:respond_to?).with(:delete_matched).and_return(false)

        expect { described_class.clear }.not_to raise_error
      end
    end

    context "when cache raises NotImplementedError" do
      it "rescues and does not re-raise" do
        cache = instance_double(ActiveSupport::Cache::MemoryStore)
        allow(Rails).to receive(:cache).and_return(cache)
        allow(cache).to receive(:respond_to?).with(:delete_matched).and_return(true)
        allow(cache).to receive(:delete_matched).and_raise(NotImplementedError, "not supported")

        expect { described_class.clear }.not_to raise_error
      end
    end

    context "when cache raises unexpected error" do
      it "rescues and does not re-raise" do
        cache = instance_double(ActiveSupport::Cache::MemoryStore)
        allow(Rails).to receive(:cache).and_return(cache)
        allow(cache).to receive(:respond_to?).with(:delete_matched).and_return(true)
        allow(cache).to receive(:delete_matched).and_raise(RuntimeError, "connection lost")

        expect { described_class.clear }.not_to raise_error
      end
    end
  end
end
