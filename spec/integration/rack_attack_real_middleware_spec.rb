# frozen_string_literal: true

require "rails_helper"
require "rack/attack"

# Regression coverage for issue #170 (third report) — "no event gets recorded in
# rails_error_dashboard_rack_attack_events".
#
# WHY THIS FILE USES THE REAL GEM AND NOT DOUBLES:
#
# Two Rack::Attack bugs have now shipped green. Both were invisible to the suite
# for the same reason: every existing spec drove the subscriber with an
# instance_double and drove the tracker by calling flush! directly. A double
# answers whatever the fixture author believed Rack::Attack does, and calling
# flush! by hand skips the question of whether anything ever CALLS it.
#
#   - #170 round 1: fixtures injected "rack.attack.match_discriminator" for a
#     plain `track` rule. Real Rack::Attack never sets that key for a Check, so
#     the blank-discriminator bug could not be reproduced by the suite.
#   - #170 round 3 (this file): the buffer was only ever drained by a LATER event
#     on the SAME thread, so one request persisted nothing. Every spec called
#     flush! explicitly, so the missing drain was invisible.
#
# These specs therefore run requests through a real Rack::Attack middleware with
# a real rule, and assert on the DATABASE without ever calling flush! by hand.
RSpec.describe "Rack::Attack real middleware integration", type: :request do
  let(:tracker) { RailsErrorDashboard::Services::RackAttackTracker }
  let(:event_model) { RailsErrorDashboard::RackAttackEvent }

  # The reporter's verbatim rule from issue #170.
  def install_markdown_track_rule!
    Rack::Attack.track("requests accepting markdown") do |req|
      req.ip if req.get? && req.env["HTTP_ACCEPT"].to_s.include?("text/markdown")
    end
  end

  # A Rack stack shaped like a real Rails app: the executor wraps Rack::Attack,
  # exactly as ActionDispatch::Executor sits above the host's middleware.
  def rack_stack
    inner = ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }
    ActionDispatch::Executor.new(Rack::Attack.new(inner), Rails.application.executor)
  end

  # Drive one request end-to-end. Closing the body is not optional:
  # ActionDispatch::Executor returns a Rack::BodyProxy and defers to_complete
  # until the SERVER closes the response body. A spec that skips body.close sees
  # the hook never fire and will wrongly conclude the fix is broken.
  def get_with_accept(stack, accept:, ip: "127.0.0.1", user_agent: "curl/8.21.0")
    env = Rack::MockRequest.env_for(
      "http://localhost/",
      "HTTP_ACCEPT" => accept,
      "HTTP_USER_AGENT" => user_agent,
      "REMOTE_ADDR" => ip
    )
    status, _headers, body = stack.call(env)
    # Let the 0.01s deadline elapse so the end-of-request hook finds the buffer
    # due. Real traffic crosses a 5s deadline without help; a spec must not.
    sleep 0.02
    body.each { |_chunk| nil }
    body.close if body.respond_to?(:close)
    status
  end

  before do
    RailsErrorDashboard.configuration.enable_rack_attack_tracking = true

    # A SMALL BUT NON-ZERO interval, deliberately.
    #
    # With 0 the deadline is already due inside `record` itself, so maybe_flush!
    # fires on the request path and dispatches ASYNC via perform_later — which
    # under the :test queue adapter enqueues a job that never runs, and the row
    # never appears. That failure mode is an artifact of the fixture, not of the
    # product, and it would have made these specs assert the opposite of the
    # truth. A tiny interval keeps the drain where the fix puts it: the
    # end-of-request executor hook, which flushes synchronously.
    RailsErrorDashboard.configuration.rack_attack_flush_interval = 0.01

    # The executor hook flushes with sync: true, but flush_all_threads! and any
    # interval flush that beats it use perform_later. Run jobs inline so the
    # assertions are about persistence, not about queue mechanics.
    @original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline

    Rack::Attack.clear_configuration
    RailsErrorDashboard::Subscribers::RackAttackSubscriber.subscribe!
    tracker.reset!
    event_model.delete_all

    # The engine registers this hook at boot; the dummy app boots before these
    # specs toggle the feature on, so register it explicitly here.
    #
    # The block runs in the executor's own context, NOT the example's, so it must
    # not close over `let` helpers such as `tracker` — name the constant.
    @hook = Rails.application.executor.to_complete do
      RailsErrorDashboard::Services::RackAttackTracker.flush_if_due!
    end
  end

  after do
    ActiveJob::Base.queue_adapter = @original_adapter if @original_adapter
    Rails.application.executor.to_complete.delete(@hook) if @hook
    RailsErrorDashboard::Subscribers::RackAttackSubscriber.unsubscribe!
    Rack::Attack.clear_configuration
    tracker.reset!
    RailsErrorDashboard.configuration.rack_attack_flush_interval = 5
    RailsErrorDashboard.configuration.enable_rack_attack_tracking = false
  end

  describe "a single matching request" do
    it "persists the event without a second request and without an explicit flush" do
      install_markdown_track_rule!

      expect {
        get_with_accept(rack_stack, accept: "text/markdown")
      }.to change { event_model.count }.from(0).to(1)

      event = event_model.first
      expect(event.rule).to eq("requests accepting markdown")
      expect(event.match_type).to eq("track")
      # Recovered via the request.ip fallback — a plain track rule is a Check and
      # Rack::Attack never writes match_discriminator for it (#170 round 1).
      expect(event.discriminator).to eq("127.0.0.1")
      expect(event.user_agent).to eq("curl/8.21.0")
      expect(event.event_count).to eq(1)
    end

    it "records nothing when the rule does not match" do
      install_markdown_track_rule!

      expect {
        get_with_accept(rack_stack, accept: "text/html")
      }.not_to change { event_model.count }
    end
  end

  describe "counts buffered on a thread that dies" do
    # Before the end-of-request drain these were lost outright, not merely
    # delayed: flush_all_threads! walks Thread.list, and a dead thread is not on
    # it. Measured 5 of 5 events lost.
    it "persists every event even though each serving thread exits" do
      install_markdown_track_rule!
      stack = rack_stack

      5.times do |i|
        Thread.new { get_with_accept(stack, accept: "text/markdown", ip: "10.0.0.#{i}") }.join
      end

      expect(event_model.sum(:event_count)).to eq(5)
      expect(event_model.count).to eq(5)
    end
  end

  describe "aggregation under repeated traffic" do
    it "collapses many requests from one client into a single counted row" do
      install_markdown_track_rule!
      stack = rack_stack

      20.times { get_with_accept(stack, accept: "text/markdown") }

      expect(event_model.count).to eq(1)
      expect(event_model.first.event_count).to eq(20)
    end
  end

  describe "flood protection" do
    it "does not write once per request when the interval has not elapsed" do
      RailsErrorDashboard.configuration.rack_attack_flush_interval = 9_999
      install_markdown_track_rule!
      stack = rack_stack

      50.times { get_with_accept(stack, accept: "text/markdown") }

      # The buffer absorbs the flood; nothing is written until the deadline.
      expect(event_model.count).to eq(0)
      expect(tracker.buffered_counts.values.sum).to eq(50)
    end
  end

  describe "thread-local hygiene (safety rule 4)" do
    it "leaves no buffered counts or deadline behind after the flush" do
      install_markdown_track_rule!

      get_with_accept(rack_stack, accept: "text/markdown")

      expect(tracker.buffered_counts).to be_empty
      expect(Thread.current[described_class_deadline_key]).to be_nil
    end

    def described_class_deadline_key
      RailsErrorDashboard::Services::RackAttackTracker::DEADLINE_THREAD_KEY
    end
  end
end
