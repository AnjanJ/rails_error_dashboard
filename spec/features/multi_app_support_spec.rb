# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Multi-App Support", type: :feature do
  describe "Application model" do
    it "can create applications" do
      app = RailsErrorDashboard::Application.create!(name: "TestApp")
      expect(app).to be_persisted
      expect(app.name).to eq("TestApp")
    end

    it "enforces unique names" do
      RailsErrorDashboard::Application.create!(name: "UniqueApp")
      expect {
        RailsErrorDashboard::Application.create!(name: "UniqueApp")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "caches find_or_create_by_name" do
      # Clear cache first
      Rails.cache.clear

      app_name = "CachedApp"

      # First call should hit DB
      app1 = RailsErrorDashboard::Application.find_or_create_by_name(app_name)

      # Second call should use cache (verify by checking cache)
      cached = Rails.cache.read("error_dashboard/application/#{app_name}")
      expect(cached).to eq(app1)

      app2 = RailsErrorDashboard::Application.find_or_create_by_name(app_name)
      expect(app2.id).to eq(app1.id)
    end
  end

  describe "ErrorLog with application" do
    let(:application) { RailsErrorDashboard::Application.create!(name: "App1") }

    it "requires application_id" do
      expect {
        RailsErrorDashboard::ErrorLog.create!(
          error_type: "TestError",
          message: "Test message",
          occurred_at: Time.current,
          resolved: false
        )
      }.to raise_error(ActiveRecord::RecordInvalid, /Application must exist/)
    end

    it "creates error with application" do
      error = RailsErrorDashboard::ErrorLog.create!(
        application_id: application.id,
        error_type: "TestError",
        message: "Test message",
        occurred_at: Time.current,
        resolved: false
      )

      expect(error).to be_persisted
      expect(error.application).to eq(application)
    end

    it "generates error hash including application_id" do
      error1 = RailsErrorDashboard::ErrorLog.create!(
        application_id: application.id,
        error_type: "TestError",
        message: "Test message",
        occurred_at: Time.current,
        resolved: false
      )

      hash1 = error1.generate_error_hash

      # Same error in different app should have different hash
      app2 = RailsErrorDashboard::Application.create!(name: "App2")
      error2 = RailsErrorDashboard::ErrorLog.create!(
        application_id: app2.id,
        error_type: "TestError",
        message: "Test message",
        occurred_at: Time.current,
        resolved: false
      )

      hash2 = error2.generate_error_hash

      expect(hash1).not_to eq(hash2)
    end
  end

  describe "find_or_increment_by_hash with application scoping" do
    let(:app1) { RailsErrorDashboard::Application.create!(name: "App1") }
    let(:app2) { RailsErrorDashboard::Application.create!(name: "App2") }

    it "creates separate errors for same hash in different apps" do
      error_hash = "test_hash_123"

      attrs1 = {
        application_id: app1.id,
        error_hash: error_hash,
        error_type: "TestError",
        message: "Test message",
        occurred_at: Time.current
      }

      attrs2 = {
        application_id: app2.id,
        error_hash: error_hash,
        error_type: "TestError",
        message: "Test message",
        occurred_at: Time.current
      }

      error1 = RailsErrorDashboard::ErrorLog.find_or_increment_by_hash(error_hash, attrs1)
      error2 = RailsErrorDashboard::ErrorLog.find_or_increment_by_hash(error_hash, attrs2)

      expect(error1.id).not_to eq(error2.id)
      expect(error1.application).to eq(app1)
      expect(error2.application).to eq(app2)
    end

    it "increments occurrence for same app" do
      error_hash = "test_hash_456"

      attrs = {
        application_id: app1.id,
        error_hash: error_hash,
        error_type: "TestError",
        message: "Test message",
        occurred_at: Time.current
      }

      error1 = RailsErrorDashboard::ErrorLog.find_or_increment_by_hash(error_hash, attrs)
      expect(error1.occurrence_count).to eq(1)

      error2 = RailsErrorDashboard::ErrorLog.find_or_increment_by_hash(error_hash, attrs)
      expect(error2.id).to eq(error1.id)
      expect(error2.occurrence_count).to eq(2)
    end

    it "handles concurrent creates without duplicates" do
      error_hash = "concurrent_hash_789"

      attrs = {
        application_id: app1.id,
        error_hash: error_hash,
        error_type: "TestError",
        message: "Concurrent test",
        occurred_at: Time.current
      }

      # Simulate concurrent requests
      errors = 5.times.map do
        Thread.new do
          RailsErrorDashboard::ErrorLog.find_or_increment_by_hash(error_hash, attrs)
        end
      end.map(&:value)

      # Should create only ONE error record
      unique_ids = errors.map(&:id).uniq
      expect(unique_ids.size).to eq(1)

      # Occurrence count should be 5
      final_error = RailsErrorDashboard::ErrorLog.find(unique_ids.first)
      expect(final_error.occurrence_count).to eq(5)
    end
  end

  describe "LogError command with auto-registration" do
    it "auto-creates application from Rails.application" do
      # Allow configuration to be stubbed
      allow(RailsErrorDashboard.configuration).to receive(:application_name).and_return("AutoApp")

      exception = StandardError.new("Auto-registered error")

      expect {
        RailsErrorDashboard::Commands::LogError.call(exception, {})
      }.to change { RailsErrorDashboard::Application.count }.by(1)

      app = RailsErrorDashboard::Application.find_by(name: "AutoApp")
      expect(app).to be_present

      error = RailsErrorDashboard::ErrorLog.last
      expect(error.application).to eq(app)
    end

    it "reuses existing application" do
      existing_app = RailsErrorDashboard::Application.create!(name: "ExistingApp")
      allow(RailsErrorDashboard.configuration).to receive(:application_name).and_return("ExistingApp")

      exception = StandardError.new("Error in existing app")

      expect {
        RailsErrorDashboard::Commands::LogError.call(exception, {})
      }.not_to change { RailsErrorDashboard::Application.count }

      error = RailsErrorDashboard::ErrorLog.last
      expect(error.application).to eq(existing_app)
    end
  end

  describe "Query objects with application filtering" do
    let!(:app1) { RailsErrorDashboard::Application.create!(name: "QueryApp1") }
    let!(:app2) { RailsErrorDashboard::Application.create!(name: "QueryApp2") }
    let!(:error1) { RailsErrorDashboard::ErrorLog.create!(application: app1, error_type: "Error1", message: "App1 error", occurred_at: Time.current, resolved: false) }
    let!(:error2) { RailsErrorDashboard::ErrorLog.create!(application: app2, error_type: "Error2", message: "App2 error", occurred_at: Time.current, resolved: false) }

    it "ErrorsList filters by application" do
      result = RailsErrorDashboard::Queries::ErrorsList.call(application_id: app1.id)
      expect(result.to_a).to include(error1)
      expect(result.to_a).not_to include(error2)
    end

    it "FilterOptions returns applications" do
      options = RailsErrorDashboard::Queries::FilterOptions.call
      expect(options[:applications]).to be_an(Array)
      expect(options[:applications].map(&:first)).to include("QueryApp1", "QueryApp2")
    end

    it "DashboardStats scopes by application" do
      stats_all = RailsErrorDashboard::Queries::DashboardStats.call
      stats_app1 = RailsErrorDashboard::Queries::DashboardStats.call(application_id: app1.id)

      expect(stats_app1).to be_a(Hash)
      # Stats for app1 should be different from all apps
      expect(stats_app1[:unresolved]).to be < stats_all[:unresolved] if stats_all[:unresolved] > 1
    end

    it "AnalyticsStats scopes by application" do
      analytics_all = RailsErrorDashboard::Queries::AnalyticsStats.call(7)
      analytics_app1 = RailsErrorDashboard::Queries::AnalyticsStats.call(7, application_id: app1.id)

      expect(analytics_app1).to be_a(Hash)
      expect(analytics_app1[:error_stats]).to be_a(Hash)
    end
  end
end
