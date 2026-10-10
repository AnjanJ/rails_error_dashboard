# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::BootErrors do
  let!(:application) { create(:application) }

  def boot_row(error_type: "Zeitwerk::NameError", message: "expected file app/models/widget.rb to define constant Widget, but didn't",
               boot: { file: "app/models/widget.rb", constant: "Widget" }, count: 1, seen: 1.hour.ago, resolved: false, app: application)
    create(:error_log, application: app, platform: "boot_crash", error_type: error_type, message: message,
           occurrence_count: count, first_seen_at: seen - 1.minute, last_seen_at: seen, occurred_at: seen, resolved: resolved,
           environment_info: { phase: "boot", boot: boot, source: "crash_capture" }.to_json)
  end

  it "lists boot crashes most recent first with the file and constant" do
    boot_row(seen: 2.days.ago)
    newest = boot_row(error_type: "SyntaxError", message: "syntax error", boot: { file: "app/models/order.rb:7" }, seen: 1.hour.ago, count: 3)

    result = described_class.call(30)

    expect(result[:entries].map { |e| e[:id] }.first).to eq(newest.id)
    expect(result[:entries].first).to include(error_type: "SyntaxError", file: "app/models/order.rb:7", constant: nil, count: 3, resolved: false)
    expect(result[:entries].last).to include(file: "app/models/widget.rb", constant: "Widget")
    expect(result[:unresolved_count]).to eq(2)
  end

  it "ignores runtime crashes and ordinary errors" do
    create(:error_log, application: application, platform: "crash_capture")
    create(:error_log, application: application, platform: "Web")
    boot_row

    expect(described_class.call(30)[:entries].size).to eq(1)
  end

  it "applies the window, the application filter and the resolved flag" do
    boot_row(seen: 40.days.ago)
    other = create(:application, name: "Other")
    boot_row(app: other)
    boot_row(resolved: true)

    expect(described_class.call(30)[:entries].size).to eq(2)
    expect(described_class.call(30)[:unresolved_count]).to eq(1)
    expect(described_class.call(30, application_id: other.id)[:entries].size).to eq(1)
    expect(described_class.call(90)[:entries].size).to eq(3)
  end

  it "tolerates rows whose environment_info is not JSON or has no boot detail" do
    create(:error_log, application: application, platform: "boot_crash", environment_info: "not json", last_seen_at: 1.hour.ago)
    create(:error_log, application: application, platform: "boot_crash", environment_info: nil, last_seen_at: 1.hour.ago)

    entries = described_class.call(30)[:entries]

    expect(entries.size).to eq(2)
    expect(entries.map { |e| e[:file] }).to eq([ nil, nil ])
  end
end
