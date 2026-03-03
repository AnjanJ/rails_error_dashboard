# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::NplusOneSummary do
  def breadcrumbs_json(*crumbs)
    crumbs.to_json
  end

  def sql_crumb(message, duration: 1.2)
    { "c" => "sql", "m" => message, "d" => duration }
  end

  def cache_crumb(message)
    { "c" => "cache", "m" => message, "d" => 0.5 }
  end

  describe ".call" do
    it "returns empty patterns when no errors exist" do
      result = described_class.call(30)
      expect(result[:patterns]).to eq([])
    end

    it "returns empty patterns when errors have no breadcrumbs" do
      create(:error_log, breadcrumbs: nil, occurred_at: 1.day.ago)
      result = described_class.call(30)
      expect(result[:patterns]).to eq([])
    end

    it "returns empty patterns when no N+1 patterns detected" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 1'),
          sql_crumb('SELECT "posts".* FROM "posts" WHERE "posts"."id" = 2')
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:patterns]).to eq([])
    end

    it "detects N+1 patterns from breadcrumbs" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 1', duration: 1.0),
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 2', duration: 1.5),
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 3', duration: 2.0)
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:patterns].size).to eq(1)
      expect(result[:patterns].first[:count]).to eq(3)
      expect(result[:patterns].first[:fingerprint]).to be_present
      expect(result[:patterns].first[:sample_query]).to include("users")
    end

    it "aggregates same fingerprint across multiple errors" do
      3.times do |i|
        create(:error_log,
          breadcrumbs: breadcrumbs_json(
            sql_crumb("SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"id\" = #{i + 1}", duration: 1.0),
            sql_crumb("SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"id\" = #{i + 4}", duration: 1.0),
            sql_crumb("SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"id\" = #{i + 7}", duration: 1.0)
          ),
          occurred_at: 1.day.ago)
      end

      result = described_class.call(30)
      expect(result[:patterns].size).to eq(1)
      expect(result[:patterns].first[:count]).to eq(9)
      expect(result[:patterns].first[:error_ids].size).to eq(3)
      expect(result[:patterns].first[:error_count]).to eq(3)
    end

    it "deduplicates error_ids" do
      error = create(:error_log,
        breadcrumbs: breadcrumbs_json(
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 1'),
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 2'),
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 3')
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:patterns].first[:error_ids]).to eq([ error.id ])
    end

    it "sorts by count descending" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 1'),
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 2'),
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 3'),
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 4'),
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 5')
        ),
        occurred_at: 1.day.ago)

      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          sql_crumb('SELECT "posts".* FROM "posts" WHERE "posts"."id" = 1'),
          sql_crumb('SELECT "posts".* FROM "posts" WHERE "posts"."id" = 2'),
          sql_crumb('SELECT "posts".* FROM "posts" WHERE "posts"."id" = 3')
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:patterns].size).to eq(2)
      expect(result[:patterns].first[:sample_query]).to include("users")
      expect(result[:patterns].last[:sample_query]).to include("posts")
    end

    it "respects time range" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          sql_crumb('SELECT "old".* FROM "old" WHERE "old"."id" = 1'),
          sql_crumb('SELECT "old".* FROM "old" WHERE "old"."id" = 2'),
          sql_crumb('SELECT "old".* FROM "old" WHERE "old"."id" = 3')
        ),
        occurred_at: 40.days.ago)

      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          sql_crumb('SELECT "recent".* FROM "recent" WHERE "recent"."id" = 1'),
          sql_crumb('SELECT "recent".* FROM "recent" WHERE "recent"."id" = 2'),
          sql_crumb('SELECT "recent".* FROM "recent" WHERE "recent"."id" = 3')
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:patterns].size).to eq(1)
      expect(result[:patterns].first[:sample_query]).to include("recent")
    end

    it "filters by application_id" do
      app1 = create(:application, name: "App1")
      app2 = create(:application, name: "App2")

      create(:error_log,
        application: app1,
        breadcrumbs: breadcrumbs_json(
          sql_crumb('SELECT "app1".* FROM "app1" WHERE "app1"."id" = 1'),
          sql_crumb('SELECT "app1".* FROM "app1" WHERE "app1"."id" = 2'),
          sql_crumb('SELECT "app1".* FROM "app1" WHERE "app1"."id" = 3')
        ),
        occurred_at: 1.day.ago)

      create(:error_log,
        application: app2,
        breadcrumbs: breadcrumbs_json(
          sql_crumb('SELECT "app2".* FROM "app2" WHERE "app2"."id" = 1'),
          sql_crumb('SELECT "app2".* FROM "app2" WHERE "app2"."id" = 2'),
          sql_crumb('SELECT "app2".* FROM "app2" WHERE "app2"."id" = 3')
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30, application_id: app1.id)
      expect(result[:patterns].size).to eq(1)
      expect(result[:patterns].first[:sample_query]).to include("app1")
    end

    it "handles malformed JSON breadcrumbs gracefully" do
      create(:error_log,
        breadcrumbs: "not valid json {{{",
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:patterns]).to eq([])
    end

    it "tracks last_seen timestamp" do
      freeze_time do
        create(:error_log,
          breadcrumbs: breadcrumbs_json(
            sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 1'),
            sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 2'),
            sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 3')
          ),
          occurred_at: 5.days.ago)

        create(:error_log,
          breadcrumbs: breadcrumbs_json(
            sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 4'),
            sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 5'),
            sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 6')
          ),
          occurred_at: 1.day.ago)

        result = described_class.call(30)
        expect(result[:patterns].first[:last_seen]).to eq(1.day.ago)
      end
    end

    it "tracks total_duration_ms across errors" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 1', duration: 5.0),
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 2', duration: 3.0),
          sql_crumb('SELECT "users".* FROM "users" WHERE "users"."id" = 3', duration: 2.0)
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:patterns].first[:total_duration_ms]).to eq(10.0)
    end

    it "ignores non-SQL breadcrumbs" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          cache_crumb("cache read: users/1"),
          cache_crumb("cache read: users/2"),
          cache_crumb("cache read: users/3")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:patterns]).to eq([])
    end
  end
end
