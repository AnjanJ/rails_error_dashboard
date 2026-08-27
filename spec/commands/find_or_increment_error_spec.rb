# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::FindOrIncrementError do
  let(:application) { RailsErrorDashboard::Application.find_or_create_by_name("Test App") }
  let(:error_hash) { "abc123def456" }
  let(:base_attributes) do
    {
      application_id: application.id,
      error_type: "NoMethodError",
      message: "undefined method 'name' for nil",
      backtrace: "app/models/user.rb:42:in 'name'",
      occurred_at: Time.current,
      error_hash: error_hash
    }
  end

  after do
    RailsErrorDashboard::ErrorLog.delete_all
  end

  describe ".call" do
    context "when no matching error exists" do
      it "creates a new error record" do
        expect {
          described_class.call(error_hash, base_attributes)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end

      it "sets occurrence_count to 1" do
        error = described_class.call(error_hash, base_attributes)
        expect(error.occurrence_count).to eq(1)
      end

      it "sets resolved to false" do
        error = described_class.call(error_hash, base_attributes)
        expect(error.resolved).to be false
      end
    end

    context "when an unresolved match exists within 24h" do
      let!(:existing) do
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            resolved: false,
            occurrence_count: 3,
            first_seen_at: 2.hours.ago,
            last_seen_at: 1.hour.ago
          )
        )
      end

      it "increments occurrence_count" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.id).to eq(existing.id)
        expect(result.occurrence_count).to eq(4)
      end

      it "updates last_seen_at" do
        freeze_time do
          result = described_class.call(error_hash, base_attributes)
          expect(result.last_seen_at).to be_within(1.second).of(Time.current)
        end
      end

      it "does not create a new record" do
        expect {
          described_class.call(error_hash, base_attributes)
        }.not_to change(RailsErrorDashboard::ErrorLog, :count)
      end
    end

    context "when a resolved match exists" do
      let!(:resolved_error) do
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            resolved: true,
            status: "resolved",
            resolved_at: 1.day.ago,
            occurrence_count: 5,
            first_seen_at: 1.week.ago,
            last_seen_at: 1.day.ago
          )
        )
      end

      it "reopens the resolved error instead of creating a new one" do
        expect {
          described_class.call(error_hash, base_attributes)
        }.not_to change(RailsErrorDashboard::ErrorLog, :count)
      end

      it "sets resolved to false" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.id).to eq(resolved_error.id)
        expect(result.resolved).to be false
      end

      it "sets status back to new" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.status).to eq("new")
      end

      it "clears resolved_at" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.resolved_at).to be_nil
      end

      it "increments occurrence_count" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.occurrence_count).to eq(6)
      end

      it "updates last_seen_at" do
        freeze_time do
          result = described_class.call(error_hash, base_attributes)
          expect(result.last_seen_at).to be_within(1.second).of(Time.current)
        end
      end

      it "preserves first_seen_at" do
        original_first_seen = resolved_error.first_seen_at
        result = described_class.call(error_hash, base_attributes)
        expect(result.first_seen_at).to be_within(1.second).of(original_first_seen)
      end

      it "sets just_reopened flag" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.just_reopened).to be true
      end

      it "sets reopened_at timestamp" do
        freeze_time do
          result = described_class.call(error_hash, base_attributes)
          if RailsErrorDashboard::ErrorLog.column_names.include?("reopened_at")
            expect(result.reopened_at).to be_within(1.second).of(Time.current)
          end
        end
      end

      it "reopens even if resolved more than 24h ago" do
        resolved_error.update!(occurred_at: 1.month.ago, last_seen_at: 1.month.ago)

        result = described_class.call(error_hash, base_attributes)
        expect(result.id).to eq(resolved_error.id)
        expect(result.resolved).to be false
      end
    end

    context "when a wont_fix match exists" do
      let!(:wont_fix_error) do
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            resolved: true,
            status: "wont_fix",
            resolved_at: 1.day.ago,
            occurrence_count: 2,
            first_seen_at: 1.week.ago,
            last_seen_at: 1.day.ago
          )
        )
      end

      it "reopens the wont_fix error" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.id).to eq(wont_fix_error.id)
        expect(result.resolved).to be false
        expect(result.status).to eq("new")
      end
    end

    context "when both unresolved and resolved matches exist" do
      let!(:unresolved_error) do
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            resolved: false,
            status: "new",
            occurrence_count: 2,
            first_seen_at: 1.hour.ago,
            last_seen_at: 30.minutes.ago
          )
        )
      end

      let!(:resolved_error) do
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            error_hash: error_hash,
            resolved: true,
            status: "resolved",
            resolved_at: 1.day.ago,
            occurrence_count: 10,
            first_seen_at: 1.week.ago,
            last_seen_at: 1.day.ago
          )
        )
      end

      it "prefers the unresolved match over resolved" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.id).to eq(unresolved_error.id)
        expect(result.occurrence_count).to eq(3)
      end
    end
  end

  describe "environment matching" do
    let(:production) { base_attributes.merge(environment: "production") }
    let(:staging) { base_attributes.merge(environment: "staging") }

    it "keeps the same hash as separate rows per environment" do
      described_class.call(error_hash, production)
      described_class.call(error_hash, staging)

      rows = RailsErrorDashboard::ErrorLog.where(error_hash: error_hash)
      expect(rows.count).to eq(2)
      expect(rows.pluck(:environment)).to contain_exactly("production", "staging")
    end

    it "increments an existing row in the same environment" do
      first = described_class.call(error_hash, production)
      second = described_class.call(error_hash, production)

      expect(second.id).to eq(first.id)
      expect(second.occurrence_count).to eq(2)
      expect(RailsErrorDashboard::ErrorLog.where(error_hash: error_hash).count).to eq(1)
    end

    it "adopts a legacy NULL-environment row and stamps it" do
      legacy = described_class.call(error_hash, base_attributes) # environment: nil
      expect(legacy.environment).to be_nil

      result = described_class.call(error_hash, production)

      expect(result.id).to eq(legacy.id)
      expect(result.occurrence_count).to eq(2)
      expect(result.environment).to eq("production")
      expect(result.error_hash).to eq(error_hash) # the hash never changes
    end

    it "prefers an exact match to adoption when a NULL row and an exact row coexist" do
      legacy = RailsErrorDashboard::ErrorLog.create!(base_attributes.merge(resolved: false, environment: nil))
      exact = RailsErrorDashboard::ErrorLog.create!(base_attributes.merge(resolved: false, environment: "production"))

      result = described_class.call(error_hash, production)

      expect(result.id).to eq(exact.id)
      expect(legacy.reload.environment).to be_nil
      expect(legacy.occurrence_count).to eq(1)
    end

    it "reopens a resolved NULL-environment row and stamps it" do
      legacy = described_class.call(error_hash, base_attributes)
      legacy.update!(resolved: true, status: "resolved", resolved_at: 1.hour.ago)

      result = described_class.call(error_hash, staging)

      expect(result.id).to eq(legacy.id)
      expect(result.resolved).to be(false)
      expect(result.environment).to eq("staging")
    end

    it "does not let a staging occurrence increment a production row" do
      prod = described_class.call(error_hash, production)
      result = described_class.call(error_hash, staging)

      expect(result.id).not_to eq(prod.id)
      expect(prod.reload.occurrence_count).to eq(1)
    end
  end

describe "occurrence context refresh (ROADMAP C2)" do
  let(:first_context) do
    {
      system_health: { gc: { count: 1 }, captured_at: "2026-08-27T09:00:00Z" }.to_json,
      breadcrumbs: [ { category: "sql", message: "SELECT 1" } ].to_json,
      local_variables: { user_id: 1 }.to_json,
      instance_variables: { "@order" => "#<Order 1>" }.to_json,
      http_method: "GET",
      hostname: "first.example.com",
      content_type: "text/html",
      request_duration_ms: 12,
      app_version: "1.0.0",
      git_sha: "aaaaaaa"
    }
  end
  let(:second_context) do
    {
      system_health: { gc: { count: 99 }, captured_at: "2026-08-27T10:00:00Z" }.to_json,
      breadcrumbs: [ { category: "cache", message: "cache read: users/42" } ].to_json,
      local_variables: { user_id: 2 }.to_json,
      instance_variables: { "@order" => "#<Order 2>" }.to_json,
      http_method: "POST",
      hostname: "second.example.com",
      content_type: "application/json",
      request_duration_ms: 340,
      app_version: "1.1.0",
      git_sha: "bbbbbbb"
    }
  end

  let!(:existing) do
    RailsErrorDashboard::ErrorLog.create!(
      base_attributes.merge(first_context).merge(
        resolved: false, occurrence_count: 1, first_seen_at: 2.hours.ago, last_seen_at: 1.hour.ago
      )
    )
  end

  it "overwrites the moment-of-failure payloads with the latest occurrence" do
    result = described_class.call(error_hash, base_attributes.merge(second_context))

    expect(result.id).to eq(existing.id)
    expect(JSON.parse(result.system_health)["gc"]["count"]).to eq(99)
    expect(JSON.parse(result.breadcrumbs).first["category"]).to eq("cache")
    expect(JSON.parse(result.local_variables)["user_id"]).to eq(2)
    expect(JSON.parse(result.instance_variables)["@order"]).to eq("#<Order 2>")
  end

  it "refreshes the HTTP context alongside request_url" do
    result = described_class.call(error_hash, base_attributes.merge(second_context))

    expect(result.http_method).to eq("POST")
    expect(result.hostname).to eq("second.example.com")
    expect(result.content_type).to eq("application/json")
    expect(result.request_duration_ms).to eq(340)
  end

  it "keeps the stored payloads when the new occurrence carries none (storm :lite / feature off)" do
    result = described_class.call(error_hash, base_attributes)

    expect(result.occurrence_count).to eq(2)
    expect(JSON.parse(result.system_health)["gc"]["count"]).to eq(1)
    expect(JSON.parse(result.breadcrumbs).first["category"]).to eq("sql")
    expect(JSON.parse(result.local_variables)["user_id"]).to eq(1)
    expect(result.hostname).to eq("first.example.com")
  end

  it "does not touch release identity or first-occurrence timestamps" do
    result = described_class.call(error_hash, base_attributes.merge(second_context))

    expect(result.app_version).to eq("1.0.0")
    expect(result.git_sha).to eq("aaaaaaa")
    expect(result.occurred_at).to be_within(1.second).of(existing.occurred_at)
    expect(result.first_seen_at).to be_within(1.second).of(existing.first_seen_at)
  end

  it "refreshes context when a resolved error is reopened" do
    existing.update!(resolved: true, status: "resolved", resolved_at: 1.day.ago)

    result = described_class.call(error_hash, base_attributes.merge(second_context))

    expect(result.resolved).to be false
    expect(JSON.parse(result.system_health)["gc"]["count"]).to eq(99)
    expect(result.http_method).to eq("POST")
  end
end
end
