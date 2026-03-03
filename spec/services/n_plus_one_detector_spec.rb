# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::NplusOneDetector do
  describe ".call" do
    it "returns empty array for nil breadcrumbs" do
      expect(described_class.call(nil)).to eq([])
    end

    it "returns empty array for empty breadcrumbs" do
      expect(described_class.call([])).to eq([])
    end

    it "returns empty array when no SQL breadcrumbs" do
      breadcrumbs = [
        { "c" => "controller", "m" => "UsersController#index" },
        { "c" => "cache", "m" => "cache read: users/1" }
      ]
      expect(described_class.call(breadcrumbs)).to eq([])
    end

    it "does NOT flag queries below default threshold (3)" do
      breadcrumbs = [
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 1", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 2", "d" => 1.5 }
      ]
      expect(described_class.call(breadcrumbs)).to eq([])
    end

    it "detects N+1 when same query pattern repeated 3+ times" do
      breadcrumbs = [
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 1", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 2", "d" => 1.5 },
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 3", "d" => 0.8 }
      ]
      results = described_class.call(breadcrumbs)
      expect(results.size).to eq(1)
      expect(results.first[:count]).to eq(3)
      expect(results.first[:fingerprint]).to include("SELECT * FROM users WHERE id = ?")
      expect(results.first[:total_duration_ms]).to be_within(0.01).of(3.3)
      expect(results.first[:sample_query]).to be_a(String)
    end

    it "normalizes numeric literals" do
      breadcrumbs = [
        { "c" => "sql", "m" => "SELECT * FROM posts WHERE id = 42", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM posts WHERE id = 99", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM posts WHERE id = 7", "d" => 1.0 }
      ]
      results = described_class.call(breadcrumbs)
      expect(results.size).to eq(1)
    end

    it "normalizes string literals" do
      breadcrumbs = [
        { "c" => "sql", "m" => "SELECT * FROM users WHERE name = 'Alice'", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM users WHERE name = 'Bob'", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM users WHERE name = 'Carol'", "d" => 1.0 }
      ]
      results = described_class.call(breadcrumbs)
      expect(results.size).to eq(1)
      expect(results.first[:fingerprint]).to include("name = ?")
    end

    it "normalizes IN clauses" do
      breadcrumbs = [
        { "c" => "sql", "m" => "SELECT * FROM posts WHERE id IN (1, 2, 3)", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM posts WHERE id IN (4, 5)", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM posts WHERE id IN (6, 7, 8, 9)", "d" => 1.0 }
      ]
      results = described_class.call(breadcrumbs)
      expect(results.size).to eq(1)
      expect(results.first[:fingerprint]).to include("IN (?)")
    end

    it "does NOT strip double-quoted PostgreSQL identifiers" do
      breadcrumbs = [
        { "c" => "sql", "m" => 'SELECT "posts"."user_id" FROM "posts" WHERE "posts"."id" = 1', "d" => 1.0 },
        { "c" => "sql", "m" => 'SELECT "posts"."user_id" FROM "posts" WHERE "posts"."id" = 2', "d" => 1.0 },
        { "c" => "sql", "m" => 'SELECT "posts"."user_id" FROM "posts" WHERE "posts"."id" = 3', "d" => 1.0 }
      ]
      results = described_class.call(breadcrumbs)
      expect(results.size).to eq(1)
      expect(results.first[:fingerprint]).to include('"posts"')
    end

    it "returns results with expected structure" do
      breadcrumbs = [
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 1", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 2", "d" => 2.0 },
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 3", "d" => 3.0 }
      ]
      result = described_class.call(breadcrumbs).first
      expect(result).to have_key(:fingerprint)
      expect(result).to have_key(:count)
      expect(result).to have_key(:total_duration_ms)
      expect(result).to have_key(:sample_query)
    end

    it "detects multiple N+1 patterns and sorts by count desc" do
      breadcrumbs = [
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 1", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 2", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 3", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM comments WHERE post_id = 1", "d" => 0.5 },
        { "c" => "sql", "m" => "SELECT * FROM comments WHERE post_id = 2", "d" => 0.5 },
        { "c" => "sql", "m" => "SELECT * FROM comments WHERE post_id = 3", "d" => 0.5 },
        { "c" => "sql", "m" => "SELECT * FROM comments WHERE post_id = 4", "d" => 0.5 },
        { "c" => "sql", "m" => "SELECT * FROM comments WHERE post_id = 5", "d" => 0.5 }
      ]
      results = described_class.call(breadcrumbs)
      expect(results.size).to eq(2)
      expect(results.first[:count]).to be >= results.last[:count]
    end

    it "respects configurable threshold parameter" do
      breadcrumbs = [
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 1", "d" => 1.0 },
        { "c" => "sql", "m" => "SELECT * FROM users WHERE id = 2", "d" => 1.0 }
      ]
      # Default threshold 3 — not detected
      expect(described_class.call(breadcrumbs)).to eq([])
      # Custom threshold 2 — detected
      results = described_class.call(breadcrumbs, threshold: 2)
      expect(results.size).to eq(1)
    end

    it "never raises (rescue => [])" do
      # Pass something weird that would cause errors
      expect(described_class.call("not an array")).to eq([])
      expect(described_class.call(123)).to eq([])
    end
  end

  describe ".normalize_sql" do
    it "replaces numeric literals with ?" do
      expect(described_class.normalize_sql("WHERE id = 42")).to eq("WHERE id = ?")
    end

    it "replaces string literals with ?" do
      expect(described_class.normalize_sql("WHERE name = 'Alice'")).to eq("WHERE name = ?")
    end

    it "replaces IN lists with ?" do
      expect(described_class.normalize_sql("WHERE id IN (1, 2, 3)")).to eq("WHERE id IN (?)")
    end

    it "preserves double-quoted identifiers" do
      sql = '"posts"."user_id"'
      expect(described_class.normalize_sql(sql)).to eq('"posts"."user_id"')
    end

    it "handles combined patterns" do
      sql = "SELECT * FROM users WHERE id = 42 AND name = 'Bob' AND status IN (1, 2)"
      normalized = described_class.normalize_sql(sql)
      expect(normalized).to eq("SELECT * FROM users WHERE id = ? AND name = ? AND status IN (?)")
    end
  end
end
