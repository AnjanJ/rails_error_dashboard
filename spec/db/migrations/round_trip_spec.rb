# frozen_string_literal: true

require "rails_helper"

# Each guarded migration, down and up on a scratch database, along both install
# histories. See spec/support/migration_round_trip.rb.
RSpec.describe "Migration round trips", type: :migration do
  own_object = {
    20261010000001 => "create_missing_translations"
  }

  before(:context) { @results = RailsErrorDashboard::MigrationRoundTrip.run(own_object.keys) }

  own_object.each do |version, name|
    RailsErrorDashboard::MigrationRoundTrip::HISTORIES.each do |history|
      context "#{name} on the #{history} history" do
        let(:trip) { @results.fetch(history).fetch(version.to_s) }

        it "adds something, or there is nothing to check" do
          expect(trip["object"]).not_to be_empty
        end

        it "takes its object away going down (migration-rollback/REQ-1, REQ-6)" do
          expect(trip["down"]).to include("error" => nil, "version_kept" => false, "left" => [])
        end

        it "brings its object back going up (migration-rollback/REQ-4)" do
          expect(trip["up"]).to eq("error" => nil, "missing" => [])
        end
      end
    end
  end
end
