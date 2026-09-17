# frozen_string_literal: true

require "rails_helper"

# LogError is not the only thing that writes exception- or request-derived
# text. Each of these writers assembles its own row, so each has to neutralise
# invalid bytes itself: on PostgreSQL the INSERT raises, on SQLite/MySQL the
# bytes are stored and break the page that shows them.
RSpec.describe "secondary writers and invalid bytes" do
  let(:bad) { "\xFF\xFE" }

  def invalid_strings_in(record)
    record.attributes.select { |_name, value| value.is_a?(String) && (!value.valid_encoding? || value.include?("\0")) }.keys
  end

  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
  end

  after do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
  end

  describe "FlushSwallowedExceptions" do
    it "stores valid raise and rescue rows" do
      RailsErrorDashboard::Commands::FlushSwallowedExceptions.call(
        raise_counts: { "Weird#{bad}Error|app/models/a#{bad}.rb:1".b => 2 },
        rescue_counts: { "Weird#{bad}Error|app/models/a#{bad}.rb:1->app/models/b#{bad}\0.rb:9".b => 3 }
      )

      rows = RailsErrorDashboard::SwallowedException.all.to_a
      expect(rows.size).to eq(2)
      rows.each { |row| expect(invalid_strings_in(row)).to eq([]) }
      expect(rows.sum { |r| r.raise_count.to_i }).to eq(2)
      expect(rows.sum { |r| r.rescue_count.to_i }).to eq(3)
    end
  end

  describe "FlushRackAttackEvents" do
    it "stores a valid event row" do
      key = RailsErrorDashboard::Services::RackAttackTracker.send(
        :build_key, "rule#{bad}".b, "throttle", "1.2.3.4#{bad}".b, "/login#{bad}\0".b, "POST", "UA #{bad}".b
      )

      RailsErrorDashboard::Commands::FlushRackAttackEvents.call(counts: { key => 4 })

      row = RailsErrorDashboard::RackAttackEvent.sole
      expect(invalid_strings_in(row)).to eq([])
      expect(row.event_count).to eq(4)
      expect(row.path).to start_with("/login")
    end
  end

  describe "DiagnosticDumpGenerator" do
    it "returns a dump whose strings are all valid, so to_json cannot raise" do
      RailsErrorDashboard.configuration.enable_breadcrumbs = true
      RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer
      RailsErrorDashboard::Services::BreadcrumbCollector.add("custom", "crumb #{bad}".b)
      Thread.current.name = "worker #{bad}".b rescue nil

      dump = RailsErrorDashboard::Services::DiagnosticDumpGenerator.call

      expect { dump.to_json }.not_to raise_error
      expect(dump.to_json).to be_valid_encoding
      expect(dump).to have_key(:captured_at)
      expect(dump).not_to have_key(:error)
    ensure
      RailsErrorDashboard::Services::BreadcrumbCollector.clear_buffer
    end
  end

  describe "FlushStormCounts" do
    it "creates a valid minimal row from an exemplar that still holds invalid bytes" do
      # The gate scrubs what it buffers; this is an entry from an older
      # release that was already in flight, or a caller of the command.
      entry = {
        "error_class" => "StormError", "message" => "storm #{bad} \0".b,
        "first_app_frame" => "app/models/s#{bad}.rb".b, "controller_name" => "c#{bad}".b,
        "action_name" => "a", "count" => 5,
        "first_seen_at" => Time.current.iso8601, "last_seen_at" => Time.current.iso8601
      }

      result = RailsErrorDashboard::Commands::FlushStormCounts.call(entries: [ entry ])

      expect(result[:success]).to be true
      row = RailsErrorDashboard::ErrorLog.sole
      expect(invalid_strings_in(row)).to eq([])
      expect(row.message).to start_with("storm ??")
    end
  end
end
