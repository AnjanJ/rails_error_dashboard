# frozen_string_literal: true

require "rails_helper"

# An ErrorLog row is a GROUP, but the breadcrumbs, health, locals, instance
# variables and request context it displays describe ONE moment of failure.
# They are refreshed by each occurrence that carries them and deliberately left
# alone by one that does not (storm :lite, or a feature switched off) -- keeping
# a useful snapshot rather than blanking it.
#
# What was missing is provenance: the page labelled that collection as the
# error's context without saying which event supplied it, so a row could show a
# new request URL beside a previous occurrence's user id and locals.
RSpec.describe "diagnostic snapshot provenance" do
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:log_error) { RailsErrorDashboard::Commands::LogError }
  let(:flush) { RailsErrorDashboard::Commands::FlushStormCounts }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.enable_storm_protection = false
    config.async_logging = false
    config.sampling_rate = 1.0
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after { RailsErrorDashboard.reset_configuration! }

  def boom(message = "provenance boom")
    StandardError.new(message).tap do |error|
      error.set_backtrace([
        "#{Rails.root}/app/models/audit.rb:12:in 'run'",
        "#{Rails.root}/app/jobs/audit_job.rb:4:in 'perform'"
      ])
    end
  end

  def storm_entry(count: 5, message: "provenance boom")
    {
      "error_class" => "StandardError",
      "message" => message,
      "first_app_frame" => "#{Rails.root}/app/models/audit.rb",
      "count" => count,
      "first_seen_at" => Time.current.iso8601,
      "last_seen_at" => Time.current.iso8601
    }
  end

  describe "a normal capture" do
    it "records when the snapshot was captured, and at what fidelity" do
      row = log_error.call(boom)

      expect(row.context_captured_at).to be_present
      expect(row.context_fidelity).to eq("full")
    end

    it "advances the provenance when a later occurrence refreshes the snapshot" do
      row = log_error.call(boom, request_url: "/first")
      first_stamp = row.reload.context_captured_at

      travel_to(2.minutes.from_now) { log_error.call(boom, request_url: "/second") }

      row.reload
      expect(row.request_url).to eq("/second")
      expect(row.context_captured_at).to be > first_stamp
    end

    # The policy the review calls reasonable: keep the earlier useful snapshot.
    # The point is that the row now SAYS the evidence is older than the counts.
    it "leaves the snapshot and its provenance alone when an occurrence carries nothing" do
      row = log_error.call(boom, request_url: "/first")
      stamp = row.reload.context_captured_at

      travel_to(2.minutes.from_now) do
        RailsErrorDashboard::Commands::FindOrIncrementError.call(
          row.error_hash, application_id: row.application_id, error_hash: row.error_hash
        )
      end

      row.reload
      expect(row.occurrence_count).to eq(2)
      expect(row.context_captured_at).to eq(stamp)
      expect(row.last_seen_at).to be > row.context_captured_at
    end
  end

  describe "a group first seen during a storm" do
    it "is marked minimal: counted exactly, but nothing was captured" do
      flush.call(entries: [ storm_entry ])

      row = logs.sole
      expect(row.context_fidelity).to eq("minimal")
      expect(row.occurrence_count).to eq(5)
      expect(row.backtrace).not_to include(":12:")
    end

    # The flush comment promised the next occurrence would fill in detail. It
    # never did: nothing replaced backtrace on an existing row, so the group
    # kept a single bare file path -- no line number, no caller frame -- for
    # its whole life.
    it "is upgraded by the next full capture, backtrace and fidelity together" do
      flush.call(entries: [ storm_entry ])
      minimal = logs.sole

      captured = log_error.call(boom)

      expect(captured.id).to eq(minimal.id)
      expect(captured.reload.occurrence_count).to eq(6)
      expect(captured.backtrace).to include(":12:")
      expect(captured.backtrace).to include("audit_job.rb")
      expect(captured.context_fidelity).to eq("full")
    end

    it "is not overwritten by a reduced storm capture" do
      flush.call(entries: [ storm_entry ])
      minimal = logs.sole
      original_backtrace = minimal.backtrace

      RailsErrorDashboard::Commands::FindOrIncrementError.call(
        minimal.error_hash,
        application_id: minimal.application_id,
        error_hash: minimal.error_hash,
        backtrace: "#{Rails.root}/app/models/audit.rb:12:in 'run'\n#{Rails.root}/app/jobs/audit_job.rb:4:in 'perform'",
        _context_fidelity: "lite"
      )

      minimal.reload
      expect(minimal.backtrace).to eq(original_backtrace)
      expect(minimal.context_fidelity).to eq("minimal")
    end
  end

  # The `||` chain in increment_existing keeps a previous occurrence's user,
  # params, agent and locals when the new one has none -- that is deliberate
  # and useful. What was wrong is the LABEL: provenance advanced whenever any
  # displayed field was refreshed, so a mixture of two events was stamped with
  # the newer event's time and called a full capture. A reader cannot tell
  # which moment the values describe.
  describe "an occurrence that refreshes only some of the snapshot" do
    it "does not call a mixture a fresh full capture" do
      log_error.call(boom, user_id: 10, request_url: "https://shop.test/first")
      row = logs.sole
      first_stamp = row.context_captured_at

      travel_to(1.minute.from_now) do
        # Anonymous, different URL, and no locals: the user and locals shown
        # afterwards still belong to the FIRST event.
        log_error.call(boom, request_url: "https://shop.test/anonymous")
      end

      row.reload
      expect(row.request_url).to eq("https://shop.test/anonymous")
      expect(row.user_id).to eq(10)

      # Either the stamp stays with the event that actually supplied the
      # retained payload, or the fidelity says the snapshot is mixed. What it
      # must not do is claim a fresh, complete capture.
      expect([ row.context_captured_at, row.context_fidelity ])
        .not_to eq([ be > first_stamp, "full" ])
      expect(row.context_fidelity).to eq("partial")
    end

    it "still calls a wholly refreshed snapshot full" do
      log_error.call(boom, user_id: 10, request_url: "https://shop.test/first")
      row = logs.sole

      travel_to(1.minute.from_now) do
        log_error.call(boom, user_id: 11, request_url: "https://shop.test/second",
                             user_agent: "Mozilla/5.0", ip_address: "10.0.0.2")
      end

      row.reload
      expect(row.user_id).to eq(11)
      expect(row.context_fidelity).to eq("full")
    end
  end

  describe "rows captured before provenance was recorded" do
    it "reports no provenance rather than inventing one" do
      row = create(:error_log, occurred_at: 1.day.ago, context_captured_at: nil, context_fidelity: nil)

      expect(row.context_captured_at).to be_nil
      expect(row.context_fidelity).to be_nil
    end
  end
end
