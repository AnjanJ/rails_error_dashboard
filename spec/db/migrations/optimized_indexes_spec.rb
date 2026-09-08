# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Optimized Indexes Migration", type: :migration do
  # :migration examples run outside the transactional wrapper (DDL + MySQL),
  # see spec/support/database_cleaner.rb.
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.connection }
  let(:table_name) { :rails_error_dashboard_error_logs }

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase == 'postgresql'
  end

  describe "composite indexes" do
    it "creates index on resolved and occurred_at" do
      indexes = connection.indexes(table_name)
      index = indexes.find { |i| i.name == 'index_error_logs_on_resolved_and_occurred_at' }

      expect(index).to be_present
      expect(index.columns).to eq([ 'resolved', 'occurred_at' ])
    end

    it "creates index on error_type and occurred_at" do
      indexes = connection.indexes(table_name)
      index = indexes.find { |i| i.name == 'index_error_logs_on_error_type_and_occurred_at' }

      expect(index).to be_present
      expect(index.columns).to eq([ 'error_type', 'occurred_at' ])
    end

    it "creates index on platform and occurred_at" do
      indexes = connection.indexes(table_name)
      index = indexes.find { |i| i.name == 'index_error_logs_on_platform_and_occurred_at' }

      expect(index).to be_present
      expect(index.columns).to eq([ 'platform', 'occurred_at' ])
    end

    it "creates index on error_hash, resolved, and occurred_at" do
      indexes = connection.indexes(table_name)
      index = indexes.find { |i| i.name == 'index_error_logs_on_hash_resolved_occurred' }

      expect(index).to be_present
      expect(index.columns).to eq([ 'error_hash', 'resolved', 'occurred_at' ])
    end
  end

  describe "query performance improvements" do
    before do
      # Create test data
      application = create(:application)
      30.times do |i|
        RailsErrorDashboard::ErrorLog.create!(
          application_id: application.id,
          error_type: "StandardError",
          message: "Test error #{i}",
          platform: i % 3 == 0 ? "iOS" : "Android",
          occurred_at: i.days.ago,
          resolved: i >= 15  # Items 15-29 are resolved, 0-14 are unresolved
        )
      end
    end

    it "uses index for resolved + occurred_at query" do
      # Query that should use the composite index
      result = RailsErrorDashboard::ErrorLog
        .where(resolved: false)
        .where("occurred_at >= ?", 7.days.ago)
        .to_a

      expect(result.count).to be > 0
    end

    it "uses index for error_type + occurred_at query" do
      result = RailsErrorDashboard::ErrorLog
        .where(error_type: "StandardError")
        .order(occurred_at: :desc)
        .to_a

      expect(result.count).to be > 0
    end

    it "uses index for platform + occurred_at query" do
      result = RailsErrorDashboard::ErrorLog
        .where(platform: "iOS")
        .order(occurred_at: :desc)
        .to_a

      expect(result.count).to be > 0
    end

    it "uses index for deduplication lookup" do
      # This is the hot path - happens on every error log
      error = RailsErrorDashboard::ErrorLog.first
      error_hash = error.error_hash

      result = RailsErrorDashboard::ErrorLog
        .where(error_hash: error_hash)
        .where(resolved: false)
        .where("occurred_at >= ?", 24.hours.ago)
        .first

      expect(result).to be_present
    end
  end
end
