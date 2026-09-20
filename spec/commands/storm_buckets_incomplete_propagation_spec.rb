# frozen_string_literal: true

require "rails_helper"

# The flag has to REACH someone.
#
# FlushStormCounts correctly degrades when the rollup table is permanently
# unavailable: it keeps the authoritative lifetime count and skips the bucket.
# But buckets_incomplete was returned in the result hash and then dropped --
# no caller persisted it, no query read it, nothing on the dashboard said so,
# and a replay lost it entirely. A figure of unknown completeness was presented
# as fact.
#
# This is the same contract affected_users_incomplete already honours for
# storm-shed occurrence rows: say the dimension is incomplete rather than
# quietly under-reporting it.
RSpec.describe "buckets_incomplete propagation" do
  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.async_logging = false
    Rails.cache.clear
  end

  after { RailsErrorDashboard.reset_configuration! }

  let(:identity) { "propagate-#{SecureRandom.hex(6)}" }

  def flush(episode: nil, batch_id: SecureRandom.hex(8))
    RailsErrorDashboard::Commands::FlushStormCounts.call(
      entries: [
        {
          "error_class" => "StormError", "message" => identity,
          "count" => 10, "opaque_identity" => identity,
          "first_seen_at" => 10.minutes.ago.iso8601,
          "last_seen_at" => Time.current.iso8601
        }
      ],
      episode: episode,
      batch_id: batch_id
    )
  end

  def episode_hash = { "started_at" => 30.minutes.ago.iso8601, "peak_rate_per_minute" => 500 }

  context "when the rollup table is permanently unavailable" do
    before { allow(RailsErrorDashboard::EventCount).to receive(:table_exists?).and_return(false) }

    it "persists the incompleteness on the storm episode" do
      flush(episode: episode_hash)

      expect(RailsErrorDashboard::StormEvent.last.buckets_incomplete).to be(true)
    end

    it "keeps it set across a later flush that also degrades" do
      flush(episode: episode_hash)
      flush(episode: episode_hash)

      expect(RailsErrorDashboard::StormEvent.last.buckets_incomplete).to be(true)
    end

    it "reports the incompleteness on the Overview stats" do
      flush(episode: episode_hash)
      Rails.cache.clear

      expect(RailsErrorDashboard::Queries::DashboardStats.call[:event_timing_incomplete]).to be(true)
    end

    # The degradation itself must not regress: the count is authoritative.
    it "still preserves the lifetime count" do
      flush(episode: episode_hash)

      expect(RailsErrorDashboard::ErrorLog.where(error_type: "StormError")
               .where("message LIKE ?", "%#{identity}%").sum(:occurrence_count)).to eq(10)
    end
  end

  # The reviewer's own reproduction, kept verbatim in shape: five events
  # yesterday with buckets working, five today with the rollup permanently
  # unavailable. This is sharper than flushing everything today -- the group
  # already exists from yesterday, so today's shed events have no per-event
  # record of their own to land on.
  context "when an existing group sheds again with buckets unavailable" do
    let(:episode) { { "started_at" => 30.minutes.ago.iso8601, "peak_rate_per_minute" => 500 } }

    def entry_at(time)
      {
        "error_class" => "StormError", "message" => identity,
        "count" => 5, "opaque_identity" => identity,
        "first_seen_at" => time.iso8601, "last_seen_at" => time.iso8601
      }
    end

    def flush_batch(batch_id)
      RailsErrorDashboard::Commands::FlushStormCounts.call(
        entries: [ entry_at(Time.current) ], episode: episode, batch_id: batch_id
      )
    end

    before do
      travel_to(1.day.ago) { flush_batch("yesterday-#{identity}") }
      allow(RailsErrorDashboard::EventCount).to receive(:table_exists?).and_return(false)
    end

    it "keeps both days of lifetime counts" do
      flush_batch("today-#{identity}")

      expect(RailsErrorDashboard::ErrorLog.where(error_type: "StormError")
               .where("message LIKE ?", "%#{identity}%").sum(:occurrence_count)).to eq(10)
    end

    it "tells the dashboard that timing evidence is incomplete" do
      flush_batch("today-#{identity}")
      Rails.cache.clear

      expect(RailsErrorDashboard::Queries::DashboardStats.call[:event_timing_incomplete]).to be(true)
    end

    # The replay returns already_applied and carries NO flag in its result
    # hash -- which is exactly why the state cannot live in that hash. It is
    # persisted on the episode, so the dashboard's answer is unchanged.
    it "survives an idempotent replay of the same batch" do
      flush_batch("today-#{identity}")
      replay = flush_batch("today-#{identity}")
      Rails.cache.clear

      expect(replay[:already_applied]).to be(true)
      expect(replay).not_to have_key(:buckets_incomplete)
      expect(RailsErrorDashboard::Queries::DashboardStats.call[:event_timing_incomplete]).to be(true)
    end
  end

  context "when buckets are writable" do
    it "does not mark the episode incomplete" do
      flush(episode: episode_hash)

      expect(RailsErrorDashboard::StormEvent.last&.buckets_incomplete).to be_falsey
    end

    it "does not claim incompleteness on the Overview stats" do
      flush(episode: episode_hash)
      Rails.cache.clear

      expect(RailsErrorDashboard::Queries::DashboardStats.call[:event_timing_incomplete]).to be_falsey
    end
  end
end
