# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::SwallowedExceptionSummary do
  let!(:application) { create(:application) }

  after do
    RailsErrorDashboard::SwallowedException.delete_all
    RailsErrorDashboard.configuration.swallowed_exception_threshold = 0.95
  end

  describe ".call" do
    it "returns entries and summary" do
      result = described_class.call(30)
      expect(result).to have_key(:entries)
      expect(result).to have_key(:summary)
    end

    it "returns empty results when no data exists" do
      result = described_class.call(30)
      expect(result[:entries]).to be_empty
      expect(result[:summary][:total_swallowed_classes]).to eq(0)
    end

    context "with swallowed exception data" do
      before do
        create(:swallowed_exception,
          application: application,
          exception_class: "Stripe::CardError",
          raise_location: "app/services/payment.rb:42",
          rescue_location: "app/services/payment.rb:45",
          raise_count: 100,
          rescue_count: 98,
          period_hour: 1.hour.ago,
          last_seen_at: 1.hour.ago)

        create(:swallowed_exception,
          application: application,
          exception_class: "Stripe::CardError",
          raise_location: "app/services/payment.rb:42",
          rescue_location: "app/services/payment.rb:45",
          raise_count: 50,
          rescue_count: 49,
          period_hour: 2.hours.ago,
          last_seen_at: 2.hours.ago)
      end

      it "aggregates counts across hourly buckets" do
        result = described_class.call(30)
        entries = result[:entries]
        expect(entries.size).to eq(1)
        expect(entries.first[:raise_count]).to eq(150)
        expect(entries.first[:rescue_count]).to eq(147)
      end

      it "calculates rescue ratio" do
        result = described_class.call(30)
        entry = result[:entries].first
        expect(entry[:rescue_ratio]).to eq(0.98)
      end

      it "returns summary stats" do
        result = described_class.call(30)
        expect(result[:summary][:total_swallowed_classes]).to eq(1)
        expect(result[:summary][:total_rescue_count]).to eq(147)
        expect(result[:summary][:total_raise_count]).to eq(150)
      end
    end

    context "filtering" do
      before do
        create(:swallowed_exception,
          application: application,
          exception_class: "HighRatio",
          raise_count: 100,
          rescue_count: 99,
          raise_location: "app/a.rb:1",
          period_hour: 1.hour.ago)

        create(:swallowed_exception,
          application: application,
          exception_class: "LowRatio",
          raise_count: 100,
          rescue_count: 10,
          raise_location: "app/b.rb:1",
          period_hour: 1.hour.ago)
      end

      it "only includes entries above threshold" do
        result = described_class.call(30)
        classes = result[:entries].map { |e| e[:exception_class] }
        expect(classes).to include("HighRatio")
        expect(classes).not_to include("LowRatio")
      end

      it "respects custom threshold" do
        RailsErrorDashboard.configuration.swallowed_exception_threshold = 0.05

        result = described_class.call(30)
        classes = result[:entries].map { |e| e[:exception_class] }
        expect(classes).to include("HighRatio", "LowRatio")
      end

      it "filters by time range" do
        create(:swallowed_exception,
          application: application,
          exception_class: "OldError",
          raise_count: 100,
          rescue_count: 99,
          raise_location: "app/c.rb:1",
          period_hour: 40.days.ago)

        result = described_class.call(30)
        classes = result[:entries].map { |e| e[:exception_class] }
        expect(classes).not_to include("OldError")
      end

      it "filters by application_id" do
        other_app = create(:application, name: "other-app")
        create(:swallowed_exception,
          application: other_app,
          exception_class: "OtherAppError",
          raise_count: 100,
          rescue_count: 99,
          raise_location: "app/d.rb:1",
          period_hour: 1.hour.ago)

        result = described_class.call(30, application_id: application.id)
        classes = result[:entries].map { |e| e[:exception_class] }
        expect(classes).to include("HighRatio")
        expect(classes).not_to include("OtherAppError")
      end
    end

    it "sorts by rescue count descending" do
      create(:swallowed_exception,
        application: application,
        exception_class: "LessFrequent",
        raise_count: 50,
        rescue_count: 48,
        raise_location: "app/a.rb:1",
        period_hour: 1.hour.ago)

      create(:swallowed_exception,
        application: application,
        exception_class: "MoreFrequent",
        raise_count: 200,
        rescue_count: 198,
        raise_location: "app/b.rb:1",
        period_hour: 1.hour.ago)

      result = described_class.call(30)
      expect(result[:entries].first[:exception_class]).to eq("MoreFrequent")
    end

    context "edge cases" do
      it "returns empty results when all entries are below threshold" do
        create(:swallowed_exception,
          application: application,
          exception_class: "LowRatio",
          raise_count: 100,
          rescue_count: 10,
          raise_location: "app/a.rb:1",
          period_hour: 1.hour.ago)

        result = described_class.call(30)
        expect(result[:entries]).to be_empty
      end

      it "handles entries with raise_count of zero" do
        create(:swallowed_exception,
          application: application,
          exception_class: "ZeroRaises",
          raise_count: 0,
          rescue_count: 0,
          raise_location: "app/a.rb:1",
          period_hour: 1.hour.ago)

        result = described_class.call(30)
        expect(result[:entries]).to be_empty
      end

      it "handles days = 0 without error" do
        create(:swallowed_exception,
          application: application,
          raise_count: 100,
          rescue_count: 99,
          raise_location: "app/a.rb:1",
          period_hour: Time.current.beginning_of_hour)

        result = described_class.call(0)
        expect(result).to have_key(:entries)
        expect(result).to have_key(:summary)
      end

      it "handles negative days without error" do
        result = described_class.call(-5)
        expect(result[:entries]).to be_empty
        expect(result[:summary][:total_swallowed_classes]).to eq(0)
      end

      it "returns safe defaults when table does not exist" do
        allow(RailsErrorDashboard::SwallowedException).to receive(:table_exists?).and_return(false)

        result = described_class.call(30)
        expect(result[:entries]).to be_empty
        expect(result[:summary][:total_rescue_count]).to eq(0)
      end
    end
  end
end
