# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::SwallowedException, type: :model do
  describe "validations" do
    it "validates presence of exception_class" do
      record = build(:swallowed_exception, exception_class: nil)
      expect(record).not_to be_valid
      expect(record.errors[:exception_class]).to include("can't be blank")
    end

    it "validates presence of raise_location" do
      record = build(:swallowed_exception, raise_location: nil)
      expect(record).not_to be_valid
      expect(record.errors[:raise_location]).to include("can't be blank")
    end

    it "validates presence of period_hour" do
      record = build(:swallowed_exception, period_hour: nil)
      expect(record).not_to be_valid
      expect(record.errors[:period_hour]).to include("can't be blank")
    end

    it "validates raise_count is non-negative" do
      record = build(:swallowed_exception, raise_count: -1)
      expect(record).not_to be_valid
    end

    it "validates rescue_count is non-negative" do
      record = build(:swallowed_exception, rescue_count: -1)
      expect(record).not_to be_valid
    end

    it "is valid with valid attributes" do
      record = build(:swallowed_exception)
      expect(record).to be_valid
    end
  end

  describe "scopes" do
    let!(:application) { create(:application) }
    let!(:recent) { create(:swallowed_exception, application: application, period_hour: 1.hour.ago) }
    let!(:old) { create(:swallowed_exception, application: application, period_hour: 10.days.ago, raise_location: "other.rb:1") }

    it ".for_application filters by application_id" do
      other_app = create(:application, name: "other-app")
      other = create(:swallowed_exception, application: other_app, raise_location: "other.rb:2")

      results = described_class.for_application(application.id)
      expect(results).to include(recent, old)
      expect(results).not_to include(other)
    end

    it ".since filters by period_hour" do
      results = described_class.since(3.days.ago)
      expect(results).to include(recent)
      expect(results).not_to include(old)
    end

    it ".recent orders by period_hour desc" do
      results = described_class.recent
      expect(results.first).to eq(recent)
    end
  end

  describe "#rescue_ratio" do
    it "returns the fraction of raises that were rescued" do
      record = build(:swallowed_exception, raise_count: 100, rescue_count: 95)
      expect(record.rescue_ratio).to eq(0.95)
    end

    it "returns 0.0 when raise_count is zero" do
      record = build(:swallowed_exception, raise_count: 0, rescue_count: 0)
      expect(record.rescue_ratio).to eq(0.0)
    end
  end

  describe "#swallowed?" do
    it "returns true when rescue ratio >= threshold" do
      record = build(:swallowed_exception, raise_count: 100, rescue_count: 96)
      expect(record.swallowed?).to be true
    end

    it "returns false when rescue ratio < threshold" do
      record = build(:swallowed_exception, raise_count: 100, rescue_count: 50)
      expect(record.swallowed?).to be false
    end

    it "accepts custom threshold" do
      record = build(:swallowed_exception, raise_count: 100, rescue_count: 80)
      expect(record.swallowed?(threshold: 0.75)).to be true
      expect(record.swallowed?(threshold: 0.85)).to be false
    end
  end

  describe "edge cases" do
    it "is valid with nil rescue_location (raise-only record)" do
      record = build(:swallowed_exception, rescue_location: nil)
      expect(record).to be_valid
    end

    it "is valid with nil application (no application association)" do
      record = build(:swallowed_exception, application: nil)
      expect(record).to be_valid
    end

    it "handles very large counts" do
      record = build(:swallowed_exception, raise_count: 999_999_999, rescue_count: 999_999_998)
      expect(record).to be_valid
      expect(record.rescue_ratio).to be_within(0.001).of(1.0)
    end
  end
end
