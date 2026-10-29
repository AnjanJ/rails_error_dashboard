# frozen_string_literal: true

require "rails_helper"

# The storm gate runs on the request thread for every error. It builds the
# gate key per event and the redacted exemplar only when the count buffer
# stores a new entry, and both must be exactly what 0.17.0 produced.
RSpec.describe RailsErrorDashboard::Services::StormProtection::Gate, "hot path" do
  let(:gate) { described_class }
  let(:hashing) { RailsErrorDashboard::Services::ErrorHashGenerator }
  let(:sanitizer) { RailsErrorDashboard::Services::EncodingSanitizer }

  before do
    RailsErrorDashboard.configuration.enable_storm_protection = true
    gate.reset!
  end

  after do
    gate.reset!
    RailsErrorDashboard.reset_configuration!
  end

  # 0.17.0's Gate.gate_parts and Gate.gate_key, verbatim: the reference the
  # new code must match, input for input.
  def reference_parts(exception, context)
    raw_message = exception.message.to_s[0, hashing::HASH_MESSAGE_LIMIT]
    sanitizer.scrub_deep(
      error_class: exception.class.name,
      opaque_identity: hashing.opaque_identity(
        error_class: exception.class.name,
        normalized_message: hashing.normalize_message(raw_message),
        frames: hashing.extract_app_frame_from_locations(exception) || hashing.extract_app_frame(exception.backtrace),
        controller_name: context[:controller_name]&.to_s,
        action_name: context[:action_name]&.to_s
      ),
      message: gate.send(:redact, sanitizer.scrub(raw_message)),
      first_app_frame: hashing.extract_app_frame_from_locations(exception) || hashing.extract_app_frame(exception.backtrace),
      controller_name: context[:controller_name]&.to_s,
      action_name: context[:action_name]&.to_s,
      custom_hash: gate.send(:custom_hash_for, exception, context),
      environment: context[:environment].to_s.strip.presence&.[](0, 64),
      capture_source: context[:_capture_source] == "client" ? "client" : "server"
    )
  end

  def reference_key(parts)
    Digest::SHA256.hexdigest("#{parts[:custom_hash] || parts[:opaque_identity]}|#{parts[:environment]}")[0..15]
  end

  def raised(klass = RuntimeError, message = "Order 42 could not be charged")
    raise klass, message
  rescue klass => e
    e
  end

  cases = {
    "a plain error" => [ RuntimeError, "Order 42 could not be charged", {} ],
    "invalid bytes in the message" => [ RuntimeError, "bad \xFF byte".dup.force_encoding("UTF-8"), {} ],
    "spaces around the environment" => [ RuntimeError, "boom", { environment: "  staging " } ],
    "a long environment" => [ RuntimeError, "boom", { environment: "e" * 80 } ],
    "controller and action names" => [ ArgumentError, "bad argument", { controller_name: :orders, action_name: "charge" } ],
    "a client capture" => [ RuntimeError, "boom", { _capture_source: "client" } ],
    "a message over 500 characters" => [ RuntimeError, "x" * 900, {} ],
    "a secret in the message" => [ RuntimeError, "login failed password=hunter2 token: Bearer abc.def", {} ]
  }

  cases.each do |label, (klass, message, context)|
    it "makes 0.17.0's gate key and exemplar for #{label} (storm-gate-hot-path/REQ-2, storm-gate-hot-path/REQ-3)" do
      exception = raised(klass, message)
      expected = reference_parts(exception, context)
      identity = gate.send(:gate_identity, exception, context)

      expect(gate.send(:gate_key_for, identity)).to eq(reference_key(expected))
      expect(gate.send(:exemplar, identity, exception, context)).to eq(expected)
    end
  end

  it "fails open on an environment with invalid bytes, as 0.17.0 did (storm-gate-hot-path/REQ-3, storm-gate-hot-path/REQ-5)" do
    # 0.17.0's String#strip raised on these bytes, so the gate fell back to
    # :full and counted nothing. The new code raises at the same point.
    exception = raised
    context = { environment: " staging\xFF ".dup.force_encoding("UTF-8") }

    expect { reference_parts(exception, context) }.to raise_error(Encoding::CompatibilityError)
    expect { gate.send(:gate_identity, exception, context) }.to raise_error(Encoding::CompatibilityError)
    expect(gate.admit!(exception, context)).to eq(:full)
  end

  it "makes 0.17.0's key and exemplar with a custom fingerprint (storm-gate-hot-path/REQ-2, storm-gate-hot-path/REQ-3)" do
    RailsErrorDashboard.configuration.custom_fingerprint = ->(e, _ctx) { "group-#{e.class.name}" }
    exception = raised
    expected = reference_parts(exception, {})
    identity = gate.send(:gate_identity, exception, {})

    expect(gate.send(:gate_key_for, identity)).to eq(reference_key(expected))
    expect(gate.send(:exemplar, identity, exception, {})).to eq(expected)
  end

  it "buffers, in count-only mode, the entry 0.17.0 buffered (storm-gate-hot-path/REQ-2)" do
    exception = raised(RuntimeError, "charge failed password=hunter2")
    expected = reference_parts(exception, { environment: "production" })
    allow(gate).to receive(:decide).and_wrap_original { |original, _state, *args| original.call(:open, *args) }

    gate.admit!(exception, { environment: "production" })
    entry = gate.send(:count_buffer).snapshot![:entries].first

    expected.each { |field, value| expect(entry[field.to_s]).to eq(value), "#{field} differs" }
    expect(entry["message"]).not_to include("hunter2")
    expect(entry["gate_key"]).to eq(reference_key(expected))
  end

  it "never redacts on the calm path (storm-gate-hot-path/REQ-1)" do
    RailsErrorDashboard.configuration.storm_fingerprint_full_per_minute = 1_000
    allow(gate).to receive(:redact).and_call_original
    exception = raised

    5.times { expect(gate.admit!(exception, {})).to eq(:full) }

    expect(gate).not_to have_received(:redact)
  end

  it "redacts once per new fingerprint in a storm, not once per event (storm-gate-hot-path/REQ-1)" do
    allow(gate).to receive(:redact).and_call_original
    exceptions = [ raised(RuntimeError, "a"), raised(ArgumentError, "b"), raised(TypeError, "c") ]

    # Past the per-fingerprint cap, then past the breaker's open threshold.
    600.times { |i| gate.admit!(exceptions[i % 3], {}) }

    expect(gate.state).to eq(:open)
    expect(gate).to have_received(:redact).exactly(3).times
  end

  it "calls the custom fingerprint lambda once per event (storm-gate-hot-path/REQ-1)" do
    calls = 0
    RailsErrorDashboard.configuration.custom_fingerprint = ->(_e, _ctx) { calls += 1; "group" }
    exception = raised

    40.times { gate.admit!(exception, {}) } # 30 full, then count-only, one new buffer entry

    expect(calls).to eq(40)
  end

  it "fails open when building the identity raises (storm-gate-hot-path/REQ-5)" do
    allow(hashing).to receive(:opaque_identity).and_raise(StandardError, "digest broke")

    expect(gate.admit!(raised, {})).to eq(:full)
  end
end
