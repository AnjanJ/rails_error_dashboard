# frozen_string_literal: true

require "rails_helper"

# The breadcrumb trail is the gem's headline investigation feature, and it was
# unavailable exactly where errors are hardest to reproduce: background jobs.
#
# init_buffer had ONE caller, the Rack middleware, so a job that never enters
# the HTTP stack had no buffer. Every subscriber early-returns on
# `unless current_buffer`, so its SQL, cache and custom crumbs were silently
# dropped and the stored error's breadcrumbs were nil.
RSpec.describe "breadcrumbs for a failing background job" do
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:collector) { RailsErrorDashboard::Services::BreadcrumbCollector }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.enable_breadcrumbs = true
    config.async_logging = false
    config.enable_storm_protection = false
    config.sampling_rate = 1.0
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
    collector.clear_buffer

    # The engine installs the around_perform at boot; the dummy app boots with
    # breadcrumbs OFF, so neither the callback nor the AS::Notifications
    # subscribers are attached here. install_job_buffer! is idempotent.
    RailsErrorDashboard::Subscribers::BreadcrumbSubscriber.install_job_buffer!
    RailsErrorDashboard::Subscribers::BreadcrumbSubscriber.subscribe!
  end

  after do
    RailsErrorDashboard::Subscribers::BreadcrumbSubscriber.unsubscribe!
    RailsErrorDashboard.reset_configuration!
    collector.clear_buffer
  end

  # Execute a job the way Active Job executes one, with a body supplied per
  # example. The gem's own tables are excluded from the SQL trail (anti-
  # recursion), so probes issue a neutral query instead.
  def run_job(name, &body)
    stub_const(name, Class.new(ActiveJob::Base) { define_method(:perform, &body) })
    ActiveJob::Base.execute(
      "job_class" => name,
      "job_id" => SecureRandom.uuid,
      "queue_name" => "default",
      "arguments" => [],
      "executions" => 0,
      "priority" => nil
    )
  end

  it "collects the job's SQL while it is running" do
    seen = nil
    run_job("SqlProbeJob") do
      ActiveRecord::Base.connection.select_value("SELECT 1")
      seen = RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a
    end

    expect(seen).to be_present
    # Crumbs use compact keys (:c category, :m message) to keep stored JSON small.
    expect(seen.map { |c| c[:c] || c["c"] }).to include("sql")
  end

  it "adds a custom breadcrumb from inside a job instead of no-opping" do
    added = nil
    run_job("CustomProbeJob") do
      RailsErrorDashboard.add_breadcrumb("checkpoint reached")
      added = RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a
    end

    expect(added.to_s).to include("checkpoint reached")
  end

  it "cleans the buffer up after perform, so nothing leaks to the next job" do
    run_job("CleanupProbeJob") { ActiveRecord::Base.connection.select_value("SELECT 1") }

    expect(collector.current_buffer).to be_nil
  end

  # The interaction this feature creates: an async capture harvests the
  # REQUEST's trail before enqueue and carries it in the payload. Now that the
  # worker thread running AsyncErrorLoggingJob has a buffer of its own, a
  # current-thread-first harvest would store the WORKER's activity in place of
  # the request's -- the trail would describe the wrong thread entirely.
  it "keeps the captured request trail rather than the worker's own" do
    RailsErrorDashboard.configuration.async_logging = true

    collector.init_buffer
    collector.add("controller", "original request trail")

    error = StandardError.new("async trail boom")
    error.set_backtrace([ "#{Rails.root}/app/models/order.rb:1:in 'save'" ])
    RailsErrorDashboard::Commands::LogError.call(error)

    # Drain and replace the buffer, standing in for the worker thread having
    # collected entirely different activity by the time the job runs.
    collector.clear_buffer
    collector.init_buffer
    collector.add("sql", "worker thread activity")

    perform_enqueued_jobs

    row = logs.find_by(message: "async trail boom")
    expect(row.breadcrumbs.to_s).to include("original request trail")
    expect(row.breadcrumbs.to_s).not_to include("worker thread activity")
  end

  # The point of the whole feature, and the one shape every other example in
  # this file misses: they assert against current_buffer DURING perform, or nil
  # AFTER it. None asserted a STORED row for a FAILING job -- which is the only
  # thing a user ever sees.
  #
  # It failed for a reason no during-perform assertion can reach: Active Job
  # reports a job error two frames OUTSIDE the callback that owns the buffer
  # (perform_now's `rescue Exception` is one frame out; the report fires from
  # the railtie's :execute around-callback, further out still), so the ensure
  # had already cleared the buffer and the row stored breadcrumbs = nil.
  it "stores the job's own trail on the row for a job that raises" do
    expect {
      run_job("StoredTrailProbeJob") do
        ActiveRecord::Base.connection.select_value("SELECT 424242 /* stored_trail_marker */")
        RailsErrorDashboard.add_breadcrumb("checkpoint before the raise")
        raise StandardError, "stored trail boom"
      end
    }.to raise_error(StandardError, "stored trail boom")

    row = logs.find_by(message: "stored trail boom")
    expect(row).not_to be_nil
    expect(row.breadcrumbs.to_s).to include("stored_trail_marker")
    expect(row.breadcrumbs.to_s).to include("checkpoint before the raise")
  end

  # A swallowed failure reports nothing, so nothing consumes the snapshot. The
  # start-of-perform reset is what stops it becoming the NEXT job's trail on a
  # pooled thread -- the exact bleed the thread-hygiene rule forbids.
  it "does not bleed a swallowed job's trail into the next job on the thread" do
    stub_const("SwallowedProbeError", Class.new(StandardError))
    stub_const("SwallowingProbeJob", Class.new(ActiveJob::Base) do
      discard_on SwallowedProbeError
      def perform
        ActiveRecord::Base.connection.select_value("SELECT 1 /* swallowed_marker */")
        raise SwallowedProbeError, "swallowed"
      end
    end)
    ActiveJob::Base.execute(
      "job_class" => "SwallowingProbeJob", "job_id" => SecureRandom.uuid,
      "queue_name" => "default", "arguments" => [], "executions" => 0, "priority" => nil
    )

    expect {
      run_job("FollowingProbeJob") do
        ActiveRecord::Base.connection.select_value("SELECT 2 /* following_marker */")
        raise StandardError, "following boom"
      end
    }.to raise_error(StandardError, "following boom")

    row = logs.find_by(message: "following boom")
    expect(row.breadcrumbs.to_s).to include("following_marker")
    expect(row.breadcrumbs.to_s).not_to include("swallowed_marker")
  end

  # The gem's own capture job runs through the same around_perform. Its buffer
  # would collect the gem's OWN write traffic -- cache reads for the
  # application record, SAVEPOINT/RELEASE pairs that the "rails_error_dashboard_"
  # substring filter cannot catch, since transaction control names no table.
  # Harmless while it was discarded; stored garbage once a trail is kept.
  it "opens no buffer for the gem's own capture job" do
    RailsErrorDashboard.configuration.async_logging = true
    collector.clear_buffer

    error = StandardError.new("self noise boom")
    error.set_backtrace([ "#{Rails.root}/app/models/order.rb:1:in 'save'" ])
    RailsErrorDashboard::Commands::LogError.call(error)
    collector.clear_buffer
    perform_enqueued_jobs

    row = logs.find_by(message: "self noise boom")
    expect(row.breadcrumbs.to_s).not_to include("SAVEPOINT")
    expect(row.breadcrumbs.to_s).not_to include("application_id")
  end

  # Nesting: a job performed inline INSIDE a request must not clear the
  # surrounding request's buffer, and its crumbs join that trail.
  it "leaves a surrounding request buffer intact when a job runs inline" do
    collector.init_buffer
    collector.add("controller", "outer request")

    run_job("InlineProbeJob") { ActiveRecord::Base.connection.select_value("SELECT 1") }

    # to_a, not harvest: harvest DRAINS the buffer, which would destroy the
    # very state this example checks survived.
    expect(collector.current_buffer).not_to be_nil, "the job must not clear a buffer it did not open"
    expect(collector.current_buffer.to_a.to_s).to include("outer request")
  end
end
