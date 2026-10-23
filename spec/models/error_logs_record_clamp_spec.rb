# frozen_string_literal: true

require "rails_helper"

# capture-hardening-0-17/REQ-3: no text value over what a MySQL TEXT column
# holds is ever written. MySQL in strict mode rejects the whole INSERT, and the
# capture path rescues it, so one oversized payload used to lose the error.
RSpec.describe RailsErrorDashboard::ErrorLogsRecord, ".clamp_text_attributes" do
  let(:limit) { described_class::TEXT_LIMIT }

  it "cuts an oversized plain-text value on a character boundary, with a marker" do
    clamped = RailsErrorDashboard::ErrorLog.clamp_text_attributes(backtrace: "é" * 40_000)

    expect(clamped[:backtrace].bytesize).to be <= limit
    expect(clamped[:backtrace]).to be_valid_encoding
    expect(clamped[:backtrace]).to end_with("[truncated]")
  end

  it "leaves an oversized JSON value out rather than cut it into something unparseable" do
    locals = { "big" => "x" * 70_000 }.to_json
    clamped = RailsErrorDashboard::ErrorLog.clamp_text_attributes(local_variables: locals, message: "boom")

    expect(clamped).to include(local_variables: nil, message: "boom")
  end

  it "leaves values under the limit, and non-text columns, untouched" do
    attributes = { message: "m" * 1_000, error_type: "x" * 70_000, occurrence_count: 3 }

    expect(RailsErrorDashboard::ErrorLog.clamp_text_attributes(attributes)).to eq(attributes)
  end

  it "applies to the occurrence-context row, which holds the same payloads" do
    clamped = RailsErrorDashboard::ErrorOccurrenceContext.clamp_text_attributes(
      breadcrumbs: [ { "m" => "y" * 70_000 } ].to_json, system_health: { "ok" => true }.to_json
    )

    expect(clamped[:breadcrumbs]).to be_nil
    expect(clamped[:system_health]).to eq({ "ok" => true }.to_json)
  end
end
