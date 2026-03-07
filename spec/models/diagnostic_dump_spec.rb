# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::DiagnosticDump do
  let(:application) { create(:application) }

  describe "validations" do
    it "is valid with all required fields" do
      dump = described_class.new(
        application: application,
        dump_data: { captured_at: Time.current.iso8601 }.to_json,
        captured_at: Time.current
      )
      expect(dump).to be_valid
    end

    it "is invalid without captured_at" do
      dump = described_class.new(
        application: application,
        dump_data: "{}",
        captured_at: nil
      )
      expect(dump).not_to be_valid
      expect(dump.errors[:captured_at]).to include("can't be blank")
    end

    it "is invalid without dump_data" do
      dump = described_class.new(
        application: application,
        dump_data: nil,
        captured_at: Time.current
      )
      expect(dump).not_to be_valid
      expect(dump.errors[:dump_data]).to include("can't be blank")
    end
  end

  describe "associations" do
    it "belongs to application" do
      dump = described_class.create!(
        application: application,
        dump_data: "{}",
        captured_at: Time.current
      )
      expect(dump.application).to eq(application)
    end
  end

  describe ".recent" do
    it "orders by captured_at desc (most recent first)" do
      old = described_class.create!(
        application: application,
        dump_data: "{}",
        captured_at: 2.hours.ago
      )
      new_dump = described_class.create!(
        application: application,
        dump_data: "{}",
        captured_at: 1.hour.ago
      )

      result = described_class.recent
      expect(result.first).to eq(new_dump)
      expect(result.last).to eq(old)
    end
  end

  describe "optional note" do
    it "can be created with a note" do
      dump = described_class.create!(
        application: application,
        dump_data: "{}",
        captured_at: Time.current,
        note: "pre-deploy"
      )
      expect(dump.note).to eq("pre-deploy")
    end

    it "can be created without a note" do
      dump = described_class.create!(
        application: application,
        dump_data: "{}",
        captured_at: Time.current
      )
      expect(dump.note).to be_nil
    end
  end
end
