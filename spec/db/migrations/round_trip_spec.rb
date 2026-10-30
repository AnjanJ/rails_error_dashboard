# frozen_string_literal: true

require "rails_helper"

# Each guarded migration, down and up on a scratch database, along both install
# histories. See spec/support/migration_round_trip.rb.
RSpec.describe "Migration round trips", type: :migration do
  own_object = {
    20260220000001 => "add_exception_cause_to_error_logs",
    20260220000002 => "add_enriched_context_to_error_logs",
    20260221000001 => "add_environment_info_to_error_logs",
    20260221000002 => "add_reopened_at_to_error_logs",
    20260303000001 => "add_breadcrumbs_to_error_logs",
    20260307000001 => "create_rails_error_dashboard_diagnostic_dumps",
    20260613000001 => "create_storm_events",
    20260326000001 => "add_issue_tracking_to_error_logs",
    20260730000001 => "create_rails_error_dashboard_rack_attack_events",
    20260824000001 => "add_user_agent_to_rack_attack_events",
    20260826000001 => "add_environment_to_error_logs",
    20260915000003 => "add_context_provenance_to_error_logs",
    20260915000004 => "create_storm_flush_batches",
    20260919000001 => "create_event_counts",
    20260920000001 => "add_buckets_incomplete_to_storm_events",
    20260920000002 => "create_event_timing_gaps",
    20261010000001 => "create_missing_translations",
    20261015000001 => "create_rails_error_dashboard_error_occurrence_contexts"
  }

  # The complete schema also creates what these add. On a fresh install their
  # own up did nothing, and a parent table's dependents were created with it,
  # so the database can refuse to drop it.
  shadowed = {
    20251224000001 => "create_rails_error_dashboard_error_logs",
    20251224081522 => "add_better_tracking_to_error_logs",
    20251224101217 => "add_controller_action_to_error_logs",
    20251225071314 => "add_optimized_indexes_to_error_logs",
    20251225085859 => "add_enhanced_metrics_to_error_logs",
    20251225093603 => "add_similarity_tracking_to_error_logs",
    20251225100236 => "create_error_occurrences",
    20251225101920 => "create_cascade_patterns",
    20251225102500 => "create_error_baselines",
    20251226020000 => "add_workflow_fields_to_error_logs",
    20251226020100 => "create_error_comments",
    20251229111223 => "add_additional_performance_indexes",
    20260106094220 => "create_rails_error_dashboard_applications",
    20260306000003 => "create_rails_error_dashboard_swallowed_exceptions",
    20260323000001 => "add_muted_to_error_logs"
  }

  # These always had up and down, so they never said "reverted" falsely. Some
  # raise on an object that's already gone, which is loud, so that isn't checked.
  already_up_and_down = {
    20251225074653 => "remove_environment_from_error_logs",
    20260106094233 => "add_application_to_error_logs",
    20260106094318 => "finalize_application_foreign_key",
    20260220000003 => "add_time_series_indexes_to_error_logs",
    20260304000001 => "add_system_health_to_error_logs",
    20260306000001 => "add_local_variables_to_error_logs",
    20260306000002 => "add_instance_variables_to_error_logs",
    20260503000001 => "backfill_resolved_status",
    20260908000001 => "add_release_to_error_occurrences",
    20260908220001 => "add_missing_postgresql_indexes_to_error_logs",
    20260915000002 => "add_issue_repo_identity_to_error_logs",
    20260917000001 => "add_last_notified_at_to_error_logs",
    20261015000002 => "add_capture_source_to_error_occurrences_and_error_logs"
  }

  # Guarded too, but with no round trip to run: the complete schema has its own
  # example below, and the others raise IrreversibleMigration.
  no_round_trip = [ 20251223000000, 20260325000001, 20260909000001, 20260915000001 ]

  foreign_key_refusal = /depend on it|foreign key/i

  # Its guard also wants application_id, which a later migration adds. So while
  # it is the newest, a second up raises, as it has since it shipped. Changing
  # what an up does is out of scope here.
  create_error_logs = 20251224000001

  # Tables others hold foreign keys to. force: :cascade would get past the
  # database here by stripping those keys, which is why the example below exists.
  parent_tables = [ create_error_logs, 20260106094220 ]

  before(:context) do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @results = RailsErrorDashboard::MigrationRoundTrip.run(own_object.keys + shadowed.keys + already_up_and_down.keys)

    # design.md falls back if this passes 60 seconds on an adapter-test row, and
    # a job's total varies by more than that between runs, so it's printed here.
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    RSpec.configuration.reporter.message(format("Migration round trips took %.1f seconds", seconds))
  end

  shared_examples "a full round trip" do
    it "adds something, or there is nothing to check" do
      expect(trip["object"]).not_to be_empty
    end

    it "takes its object away going down (migration-rollback/REQ-1, REQ-6)" do
      expect(trip["down"]).to include("error" => nil, "version_kept" => false, "left" => [])
    end

    it "does nothing going down with its object already gone (migration-rollback/REQ-2)" do
      expect(trip["down_again"]).to eq("error" => nil, "changed" => false)
    end
  end

  shared_examples "a down that never reports a false success" do
    it "goes, or fails on the foreign key and stays recorded (migration-rollback/REQ-1, REQ-6)" do
      down = trip["down"]

      if down["error"]
        expect(down["error"]).to match(foreign_key_refusal)
        expect(down["version_kept"]).to be(true)
      else
        expect(down).to include("version_kept" => false, "left" => [])
      end
    end
  end

  shared_examples "a way back up" do |version|
    it "ends with its object present (migration-rollback/REQ-4)" do
      expect(trip["up"]).to eq("error" => nil, "missing" => [])
    end

    if version == create_error_logs
      it "changes nothing on a second up, at worst refusing a table that exists (migration-rollback/REQ-3)" do
        expect(trip["up_again"]["changed"]).to be(false)
        expect(trip["up_again"]["error"]).to be_nil.or match(/already exists/i)
      end
    else
      it "does nothing going up with its object already there (migration-rollback/REQ-3)" do
        expect(trip["up_again"]).to eq("error" => nil, "changed" => false)
      end
    end
  end

  (own_object.merge(shadowed)).each do |version, name|
    it "#{name} goes down on a database with no tables (migration-rollback/REQ-2)" do
      expect(@results.fetch("empty").fetch(version.to_s)).to be_nil
    end

    context "#{name} on the upgrade history" do
      let(:trip) { @results.fetch("upgrade").fetch(version.to_s) }

      it_behaves_like "a full round trip"
      it_behaves_like "a way back up", version
    end
  end

  own_object.each do |version, name|
    context "#{name} on the fresh history" do
      let(:trip) { @results.fetch("fresh").fetch(version.to_s) }

      it_behaves_like "a full round trip"
      it_behaves_like "a way back up", version
    end
  end

  shadowed.each do |version, name|
    context "#{name} on the fresh history" do
      let(:trip) { @results.fetch("fresh").fetch(version.to_s) }

      it_behaves_like "a down that never reports a false success"

      if parent_tables.include?(version)
        it "is refused while other tables depend on it (migration-rollback/REQ-1)" do
          skip "SQLite allows the drop while the dependents are empty" if RailsErrorDashboard::TestSchema.sqlite?

          expect(trip["down"]["error"]).to match(foreign_key_refusal)
        end
      end

      it_behaves_like "a way back up", version
    end
  end

  already_up_and_down.each do |version, name|
    context "#{name} on the upgrade history" do
      let(:trip) { @results.fetch("upgrade").fetch(version.to_s) }

      it "takes what it added away going down (migration-rollback/REQ-6)" do
        expect(trip["down"]).to include("error" => nil, "version_kept" => false, "left" => [])
      end

      it_behaves_like "a way back up", version
    end

    context "#{name} on the fresh history" do
      let(:trip) { @results.fetch("fresh").fetch(version.to_s) }

      it_behaves_like "a down that never reports a false success"
    end
  end

  it "runs every migration with an existence check, or says why not (migration-rollback/REQ-6)" do
    guarded = Dir[RailsErrorDashboard::Engine.root.join("db/migrate/*.rb")].select do |file|
      File.read(file).match?(/\w+_exists\?/)
    end

    expect(guarded.map { |file| File.basename(file)[/\A\d+/].to_i }).to match_array(
      own_object.keys + shadowed.keys + already_up_and_down.keys + no_round_trip
    )
  end

  RailsErrorDashboard::MigrationRoundTrip::HISTORIES.each do |history|
    it "ends the #{history} walk where a plain run ends, so no round trip hid the next one's state (migration-rollback/REQ-6)" do
      expect(@results.fetch("walks_end_clean")).to include(history => true)
    end
  end

  it "keeps the complete schema's down dropping exactly its seven tables (migration-rollback/REQ-5)" do
    expect(@results.fetch("complete_schema")).to eq(
      "error" => nil,
      "left" => [],
      "dropped" => %w[
        rails_error_dashboard_applications
        rails_error_dashboard_cascade_patterns
        rails_error_dashboard_error_baselines
        rails_error_dashboard_error_comments
        rails_error_dashboard_error_logs
        rails_error_dashboard_error_occurrences
        rails_error_dashboard_swallowed_exceptions
      ]
    )
  end
end
