# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::ReleaseTimeline do
  let!(:app) { create(:application) }

  describe ".call" do
    it "returns releases and summary keys" do
      result = described_class.call(30)
      expect(result).to have_key(:releases)
      expect(result).to have_key(:summary)
    end

    it "returns empty results when no version data exists" do
      create(:error_log, application: app)

      result = described_class.call(30)
      expect(result[:releases]).to be_empty
      expect(result[:summary][:total_releases]).to eq(0)
    end

    context "with versioned error data" do
      before do
        # v1.0.0: 3 errors, 2 unique types, oldest release
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", git_sha: "aaa111", error_type: "NoMethodError",
          error_hash: "hash_a", occurred_at: 20.days.ago)
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", git_sha: "aaa111", error_type: "NoMethodError",
          error_hash: "hash_a", occurred_at: 18.days.ago)
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", git_sha: "aaa111", error_type: "TypeError",
          error_hash: "hash_b", occurred_at: 15.days.ago)

        # v1.1.0: 2 errors, 1 new type + 1 from v1.0.0
        create(:error_log, :with_version, application: app,
          app_version: "1.1.0", git_sha: "bbb222", error_type: "NoMethodError",
          error_hash: "hash_a", occurred_at: 10.days.ago)
        create(:error_log, :with_version, application: app,
          app_version: "1.1.0", git_sha: "bbb222", error_type: "RuntimeError",
          error_hash: "hash_c", occurred_at: 8.days.ago)

        # v1.2.0: 1 error, 1 new type — most recent release
        create(:error_log, :with_version, application: app,
          app_version: "1.2.0", git_sha: "ccc333", error_type: "ArgumentError",
          error_hash: "hash_d", occurred_at: 2.days.ago)
      end

      it "lists releases in reverse chronological order (newest first)" do
        result = described_class.call(30, application_id: app.id)
        versions = result[:releases].map { |r| r[:version] }
        expect(versions).to eq([ "1.2.0", "1.1.0", "1.0.0" ])
      end

      it "counts total errors per release" do
        result = described_class.call(30, application_id: app.id)
        counts = result[:releases].map { |r| [ r[:version], r[:total_errors] ] }.to_h
        expect(counts["1.0.0"]).to eq(3)
        expect(counts["1.1.0"]).to eq(2)
        expect(counts["1.2.0"]).to eq(1)
      end

      it "counts unique error types per release" do
        result = described_class.call(30, application_id: app.id)
        types = result[:releases].map { |r| [ r[:version], r[:unique_error_types] ] }.to_h
        expect(types["1.0.0"]).to eq(2)
        expect(types["1.1.0"]).to eq(2)
        expect(types["1.2.0"]).to eq(1)
      end

      it "calculates first_seen and last_seen per release" do
        result = described_class.call(30, application_id: app.id)
        v100 = result[:releases].find { |r| r[:version] == "1.0.0" }
        expect(v100[:first_seen]).to be_within(1.second).of(20.days.ago)
        expect(v100[:last_seen]).to be_within(1.second).of(15.days.ago)
      end

      it "includes git_shas" do
        result = described_class.call(30, application_id: app.id)
        v100 = result[:releases].find { |r| r[:version] == "1.0.0" }
        expect(v100[:git_shas]).to include("aaa111")
      end

      it "marks the most recent release as current" do
        result = described_class.call(30, application_id: app.id)
        current = result[:releases].find { |r| r[:current] }
        expect(current[:version]).to eq("1.2.0")
        non_current = result[:releases].reject { |r| r[:current] }
        expect(non_current.size).to eq(2)
      end

      it "returns summary with current version and total releases" do
        result = described_class.call(30, application_id: app.id)
        expect(result[:summary][:total_releases]).to eq(3)
        expect(result[:summary][:current_version]).to eq("1.2.0")
        expect(result[:summary][:avg_errors_per_release]).to eq(2.0)
      end
    end

    context "new errors detection" do
      before do
        # hash_a first appears in v1.0.0
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", error_type: "NoMethodError",
          error_hash: "hash_a", occurred_at: 20.days.ago)

        # hash_a also appears in v1.1.0 — NOT new
        create(:error_log, :with_version, application: app,
          app_version: "1.1.0", error_type: "NoMethodError",
          error_hash: "hash_a", occurred_at: 10.days.ago)

        # hash_c first appears in v1.1.0 — NEW
        create(:error_log, :with_version, application: app,
          app_version: "1.1.0", error_type: "RuntimeError",
          error_hash: "hash_c", occurred_at: 8.days.ago)
      end

      it "identifies errors whose error_hash first appeared in a given version" do
        result = described_class.call(30, application_id: app.id)
        v110 = result[:releases].find { |r| r[:version] == "1.1.0" }
        expect(v110[:new_error_count]).to eq(1) # only hash_c is new
      end

      it "counts all errors in the first version as new" do
        result = described_class.call(30, application_id: app.id)
        v100 = result[:releases].find { |r| r[:version] == "1.0.0" }
        expect(v100[:new_error_count]).to eq(1) # hash_a is new to v1.0.0
      end
    end

    context "stability indicator" do
      before do
        # v1.0.0: 2 errors (average)
        2.times do |i|
          create(:error_log, :with_version, application: app,
            app_version: "1.0.0", error_hash: "hash_#{i}",
            occurred_at: 20.days.ago)
        end

        # v1.1.0: 2 errors (average)
        2.times do |i|
          create(:error_log, :with_version, application: app,
            app_version: "1.1.0", error_hash: "hash_10#{i}",
            occurred_at: 10.days.ago)
        end

        # v1.2.0: 10 errors (5x average — red)
        10.times do |i|
          create(:error_log, :with_version, application: app,
            app_version: "1.2.0", error_hash: "hash_20#{i}",
            occurred_at: 2.days.ago)
        end
      end

      it "marks low error releases as stable (green)" do
        result = described_class.call(30, application_id: app.id)
        v100 = result[:releases].find { |r| r[:version] == "1.0.0" }
        expect(v100[:stability]).to eq(:green)
      end

      it "marks high error releases as problematic (red)" do
        result = described_class.call(30, application_id: app.id)
        v120 = result[:releases].find { |r| r[:version] == "1.2.0" }
        expect(v120[:stability]).to eq(:red)
        expect(v120[:problematic]).to be true
      end
    end

    context "release comparison (delta)" do
      before do
        3.times do |i|
          create(:error_log, :with_version, application: app,
            app_version: "1.0.0", error_hash: "hash_#{i}",
            occurred_at: 20.days.ago)
        end

        5.times do |i|
          create(:error_log, :with_version, application: app,
            app_version: "1.1.0", error_hash: "hash_10#{i}",
            occurred_at: 10.days.ago)
        end
      end

      it "calculates error count delta between consecutive releases" do
        result = described_class.call(30, application_id: app.id)
        v110 = result[:releases].find { |r| r[:version] == "1.1.0" }
        expect(v110[:delta_from_previous]).to eq(2) # 5 - 3
      end

      it "calculates percentage change" do
        result = described_class.call(30, application_id: app.id)
        v110 = result[:releases].find { |r| r[:version] == "1.1.0" }
        expect(v110[:delta_percentage]).to be_within(0.1).of(66.7) # (5-3)/3 * 100
      end

      it "sets nil delta for the oldest release" do
        result = described_class.call(30, application_id: app.id)
        v100 = result[:releases].find { |r| r[:version] == "1.0.0" }
        expect(v100[:delta_from_previous]).to be_nil
      end
    end

    context "filters" do
      it "respects the days parameter" do
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", occurred_at: 40.days.ago)
        create(:error_log, :with_version, application: app,
          app_version: "1.1.0", occurred_at: 5.days.ago)

        result = described_class.call(30, application_id: app.id)
        versions = result[:releases].map { |r| r[:version] }
        expect(versions).to include("1.1.0")
        expect(versions).not_to include("1.0.0")
      end

      it "filters by application_id" do
        other_app = create(:application, name: "other-app")
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", occurred_at: 5.days.ago)
        create(:error_log, :with_version, application: other_app,
          app_version: "2.0.0", occurred_at: 5.days.ago)

        result = described_class.call(30, application_id: app.id)
        versions = result[:releases].map { |r| r[:version] }
        expect(versions).to include("1.0.0")
        expect(versions).not_to include("2.0.0")
      end
    end

    context "edge cases" do
      it "handles a single release" do
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", error_hash: "hash_a", occurred_at: 5.days.ago)

        result = described_class.call(30, application_id: app.id)
        expect(result[:releases].size).to eq(1)
        release = result[:releases].first
        expect(release[:current]).to be true
        expect(release[:delta_from_previous]).to be_nil
        expect(release[:delta_percentage]).to be_nil
      end

      it "counts all distinct hashes as new when all errors are the same version" do
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", error_hash: "hash_a", occurred_at: 5.days.ago)
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", error_hash: "hash_b", occurred_at: 4.days.ago)

        result = described_class.call(30, application_id: app.id)
        expect(result[:releases].first[:new_error_count]).to eq(2)
      end

      it "excludes errors with empty string app_version" do
        create(:error_log, application: app, app_version: "", occurred_at: 5.days.ago)
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", occurred_at: 5.days.ago)

        result = described_class.call(30, application_id: app.id)
        versions = result[:releases].map { |r| r[:version] }
        expect(versions).to eq([ "1.0.0" ])
      end

      it "handles days=0 without error" do
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", occurred_at: Time.current)

        result = described_class.call(0, application_id: app.id)
        expect(result).to have_key(:releases)
        expect(result).to have_key(:summary)
      end

      it "handles negative days without error" do
        result = described_class.call(-5)
        expect(result[:releases]).to be_empty
        expect(result[:summary][:total_releases]).to eq(0)
      end

      it "returns zero delta when consecutive releases have equal error counts" do
        2.times do |i|
          create(:error_log, :with_version, application: app,
            app_version: "1.0.0", error_hash: "hash_#{i}", occurred_at: 20.days.ago)
        end
        2.times do |i|
          create(:error_log, :with_version, application: app,
            app_version: "1.1.0", error_hash: "hash_10#{i}", occurred_at: 10.days.ago)
        end

        result = described_class.call(30, application_id: app.id)
        v110 = result[:releases].find { |r| r[:version] == "1.1.0" }
        expect(v110[:delta_from_previous]).to eq(0)
        expect(v110[:delta_percentage]).to eq(0.0)
      end

      it "assigns yellow stability for releases between 1x and 2x average" do
        # v1.0.0: 1 error, v1.1.0: 3 errors — avg = 2, v1.1.0 is 1.5x avg → yellow
        create(:error_log, :with_version, application: app,
          app_version: "1.0.0", error_hash: "hash_a", occurred_at: 20.days.ago)
        3.times do |i|
          create(:error_log, :with_version, application: app,
            app_version: "1.1.0", error_hash: "hash_1#{i}", occurred_at: 10.days.ago)
        end

        result = described_class.call(30, application_id: app.id)
        v110 = result[:releases].find { |r| r[:version] == "1.1.0" }
        expect(v110[:stability]).to eq(:yellow)
      end

      it "handles very long version strings" do
        long_version = "v" * 500
        create(:error_log, :with_version, application: app,
          app_version: long_version, occurred_at: 5.days.ago)

        result = described_class.call(30, application_id: app.id)
        expect(result[:releases].first[:version]).to eq(long_version)
      end
    end

    context "column guards" do
      it "returns empty results when app_version column does not exist" do
        allow(RailsErrorDashboard::ErrorLog).to receive(:column_names).and_return([])

        result = described_class.call(30)
        expect(result[:releases]).to be_empty
        expect(result[:summary][:total_releases]).to eq(0)
      end
    end

    context "error handling" do
      it "rescues exceptions and returns safe defaults" do
        allow(RailsErrorDashboard::ErrorLog).to receive(:where).and_raise(StandardError, "boom")

        result = described_class.call(30)
        expect(result[:releases]).to be_empty
        expect(result[:summary][:total_releases]).to eq(0)
      end
    end
  end
end
