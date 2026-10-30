# frozen_string_literal: true

require "rails_helper"

# Each guarded migration, down and up on a scratch database, along both install
# histories. See spec/support/migration_round_trip.rb.
RSpec.describe "Migration round trips", type: :migration do
  own_object = {
    20260307000001 => "create_rails_error_dashboard_diagnostic_dumps",
    20260613000001 => "create_storm_events",
    20260730000001 => "create_rails_error_dashboard_rack_attack_events",
    20260824000001 => "add_user_agent_to_rack_attack_events",
    20260826000001 => "add_environment_to_error_logs",
    20260915000004 => "create_storm_flush_batches",
    20260919000001 => "create_event_counts",
    20260920000001 => "add_buckets_incomplete_to_storm_events",
    20260920000002 => "create_event_timing_gaps",
    20261010000001 => "create_missing_translations",
    20261015000001 => "create_rails_error_dashboard_error_occurrence_contexts"
  }

  before(:context) { @results = RailsErrorDashboard::MigrationRoundTrip.run(own_object.keys) }

  own_object.each do |version, name|
    it "#{name} goes down on a database with no tables (migration-rollback/REQ-2)" do
      expect(@results.fetch("empty").fetch(version.to_s)).to be_nil
    end

    RailsErrorDashboard::MigrationRoundTrip::HISTORIES.each do |history|
      context "#{name} on the #{history} history" do
        let(:trip) { @results.fetch(history).fetch(version.to_s) }

        it "adds something, or there is nothing to check" do
          expect(trip["object"]).not_to be_empty
        end

        it "takes its object away going down (migration-rollback/REQ-1, REQ-6)" do
          expect(trip["down"]).to include("error" => nil, "version_kept" => false, "left" => [])
        end

        it "does nothing going down with its object already gone (migration-rollback/REQ-2)" do
          expect(trip["down_again"]).to eq("error" => nil, "changed" => false)
        end

        it "brings its object back going up (migration-rollback/REQ-4)" do
          expect(trip["up"]).to eq("error" => nil, "missing" => [])
        end

        it "does nothing going up with its object already there (migration-rollback/REQ-3)" do
          expect(trip["up_again"]).to eq("error" => nil, "changed" => false)
        end
      end
    end
  end
end
