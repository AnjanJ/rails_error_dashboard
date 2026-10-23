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

    # "Won't fix" means "we know it recurs and have decided not to act". It
    # used to hold for 24 hours (while the row still matched as unresolved) and
    # was then thrown away by a reopen. It is now sticky: recurrences are
    # counted on the row, at any age, and nothing else about it changes.
    context "when a wont_fix match exists" do
      def wont_fix_row(**overrides)
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            { resolved: false, status: "wont_fix", occurrence_count: 2,
              first_seen_at: 1.week.ago, last_seen_at: 1.hour.ago, occurred_at: 1.hour.ago }.merge(overrides)
          )
        )
      end

      it "absorbs a recurrence an hour later without changing the status" do
        row = wont_fix_row

        result = described_class.call(error_hash, base_attributes)

        expect(result.id).to eq(row.id)
        expect(result.occurrence_count).to eq(3)
        expect(result.status).to eq("wont_fix")
        expect(result.reopened_at).to be_nil
        expect(result.just_reopened).to be_falsey
        expect(result.last_seen_at).to be_within(2.seconds).of(Time.current)
      end

      # The group identity index is present in the dummy schema, so this also
      # proves the absorbing row does not collide with it.
      it "still absorbs a recurrence three days later, with no new row" do
        row = wont_fix_row(occurred_at: 3.days.ago, last_seen_at: 3.days.ago)

        expect {
          result = described_class.call(error_hash, base_attributes)
          expect(result.id).to eq(row.id)
          expect(result.status).to eq("wont_fix")
          expect(result.reopened_at).to be_nil
          expect(result.just_reopened).to be_falsey
        }.not_to change(RailsErrorDashboard::ErrorLog, :count)

        expect(row.reload.occurrence_count).to eq(3)
      end

      it "absorbs a legacy wont_fix row that was stored with resolved: true" do
        row = wont_fix_row(resolved: true, resolved_at: 1.day.ago, occurred_at: 3.days.ago)

        result = described_class.call(error_hash, base_attributes)

        expect(result.id).to eq(row.id)
        expect(result.status).to eq("wont_fix")
        expect(result.occurrence_count).to eq(3)
      end

      it "prefers the wont_fix row over an unresolved sibling" do
        sticky = wont_fix_row(occurred_at: 3.days.ago)
        sibling = RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(resolved: false, status: "new", occurrence_count: 1, occurred_at: 10.minutes.ago)
        )

        result = described_class.call(error_hash, base_attributes)

        expect(result.id).to eq(sticky.id)
        expect(sibling.reload.occurrence_count).to eq(1)
      end

      it "does not absorb another application's error" do
        wont_fix_row
        other = RailsErrorDashboard::Application.find_or_create_by_name("Other App")

        expect {
          described_class.call(error_hash, base_attributes.merge(application_id: other.id))
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end

      it "matches the environment exactly first, and adopts a legacy NULL-environment row" do
        skip "environment column not migrated" unless RailsErrorDashboard::ErrorLog.column_names.include?("environment")

        legacy = wont_fix_row(environment: nil, occurred_at: 3.days.ago)
        production = wont_fix_row(environment: "production", occurred_at: 2.days.ago)

        hit = described_class.call(error_hash, base_attributes.merge(environment: "production"))
        expect(hit.id).to eq(production.id)

        expect {
          described_class.call(error_hash, base_attributes.merge(environment: "staging"))
        }.not_to change(RailsErrorDashboard::ErrorLog, :count)
        expect(legacy.reload.environment).to eq("staging")
        expect(legacy.status).to eq("wont_fix")
      end
    end

    context "when a resolved match exists next to the wont_fix rule" do
      it "still reopens a resolved error (regression pin)" do
        resolved = RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(resolved: true, status: "resolved", resolved_at: 1.day.ago,
                                occurrence_count: 2, occurred_at: 3.days.ago)
        )

        result = described_class.call(error_hash, base_attributes)

        expect(result.id).to eq(resolved.id)
        expect(result.status).to eq("new")
        expect(result.resolved).to be false
        expect(result.just_reopened).to be true
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

    # functional-fixes-0-17/REQ-3: resolved rows from before group_window
    # existed keep it NULL, and the unique group-identity index (unresolved
    # rows only) folds NULL into one '' bucket. Reopening one parks it there,
    # and its old occurred_at keeps the 24 h lookup from ever matching it
    # again, so the next recurrence reopened the NEXT legacy row -- and that
    # UPDATE violated the index. Every later capture of the error was dropped.
    context "when reopening a resolved row would collide with an unresolved row of the same identity" do
      let!(:legacy_rows) do
        [ 10, 5 ].map do |days_ago|
          RailsErrorDashboard::ErrorLog.create!(
            base_attributes.merge(occurred_at: days_ago.days.ago, first_seen_at: days_ago.days.ago,
                                  last_seen_at: days_ago.days.ago)
          ).tap do |row|
            row.update_columns(resolved: true, status: "resolved", resolved_at: (days_ago - 1).days.ago,
                               group_window: nil)
          end
        end
      end
      let(:newest_legacy_row) { legacy_rows.last }

      it "counts every recurrence on the unresolved row instead of raising" do
        # MySQL has no partial indexes, so the index is never built there and
        # a reopen cannot collide: each old row is simply reopened in turn.
        unless RailsErrorDashboard::ErrorLog.connection.index_name_exists?(
          RailsErrorDashboard::ErrorLog.table_name, "index_error_logs_on_group_identity"
        )
          skip "no group identity index on this adapter, so a reopen cannot collide"
        end

        results = Array.new(3) { described_class.call(error_hash, base_attributes.merge(occurred_at: Time.current)) }

        expect(results.map(&:id).uniq).to eq([ newest_legacy_row.id ])
        open_rows = RailsErrorDashboard::ErrorLog.where(error_hash: error_hash, resolved: false)
        expect(open_rows.pluck(:id)).to eq([ newest_legacy_row.id ])
        # 1 when it was created, then the reopen and two claimed recurrences
        expect(newest_legacy_row.reload.occurrence_count).to eq(4)
      end

      context "through LogError, which stamps the environment" do
        before do
          config = RailsErrorDashboard.configuration
          config.async_logging = false
          config.enable_storm_protection = false
          config.application_name = application.name
          allow(RailsErrorDashboard::Services::ErrorHashGenerator).to receive(:call).and_return(error_hash)
        end

        after do
          RailsErrorDashboard::ErrorOccurrence.delete_all
          RailsErrorDashboard.reset_configuration!
        end

        it "records every recurrence" do
          3.times do
            raise NoMethodError, "undefined method 'name' for nil"
          rescue NoMethodError => e
            RailsErrorDashboard::Commands::LogError.call(e, {})
          end

          expect(RailsErrorDashboard::ErrorLog.where(error_hash: error_hash).sum(:occurrence_count)).to eq(2 + 3)
        end
      end
    end
  end

  # The lookup and the write must hold one row lock across both, or two
  # processes each read count N and each write N + 1. Only separate
  # connections can show that: Rails pins every thread to the connection that
  # holds the test transaction, so a transactional example serialises the
  # threads itself. :non_transactional runs this group on committed rows (see
  # spec/support/database_cleaner.rb).
  #
  # SQLite ignores FOR UPDATE, and before Rails 8.0 its deferred transactions
  # deadlock on a read-then-write race instead of queueing, so the example runs
  # where the lock does something: the PostgreSQL and MySQL CI rows.
  describe "concurrent captures on separate connections", :non_transactional do
    self.use_transactional_tests = false

    # Same application and environment as the captures, so every thread takes
    # the find_unresolved -> increment_existing path.
    let(:capture) { base_attributes.merge(environment: "production") }
    let!(:row) do
      RailsErrorDashboard::ErrorLog.create!(capture.merge(resolved: false, occurrence_count: 1))
    end

    before do
      if RailsErrorDashboard::ErrorLog.connection.adapter_name.match?(/sqlite/i)
        skip "SQLite ignores FOR UPDATE, so the row lock can't be shown here"
      end
    end

    it "keeps one row and counts every capture (test-gaps-0-17/REQ-1)" do
      # Widen the gap between the read and the write, so a lookup without the
      # row lock loses an update on every run, not just sometimes.
      allow_any_instance_of(described_class).to receive(:increment_existing).and_wrap_original do |m, *args|
        sleep 0.2
        m.call(*args)
      end

      start = Concurrent::CountDownLatch.new(1)
      threads = Array.new(4) do
        Thread.new do
          RailsErrorDashboard::ErrorLog.connection_pool.with_connection do
            start.wait
            described_class.call(error_hash, capture.merge(occurred_at: Time.current))
          end
        end
      end
      start.count_down
      threads.each(&:value)

      expect(RailsErrorDashboard::ErrorLog.where(error_hash: error_hash).count).to eq(1)
      expect(row.reload.occurrence_count).to eq(1 + 4)
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
