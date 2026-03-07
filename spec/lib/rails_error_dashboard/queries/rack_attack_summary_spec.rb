# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::RackAttackSummary do
  def breadcrumbs_json(*crumbs)
    crumbs.to_json
  end

  def rack_attack_crumb(rule:, type: "throttle", discriminator: "1.2.3.4", path: "/login", method: "POST")
    {
      "c" => "rack_attack",
      "m" => "#{type}: #{rule} (#{discriminator}) #{method} #{path}",
      "meta" => {
        "rule" => rule,
        "type" => type,
        "discriminator" => discriminator,
        "path" => path,
        "method" => method
      }
    }
  end

  def sql_crumb(message)
    { "c" => "sql", "m" => message, "d" => 1.2 }
  end

  describe ".call" do
    it "returns empty events when no errors exist" do
      result = described_class.call(30)
      expect(result[:events]).to eq([])
    end

    it "returns empty events when errors have no breadcrumbs" do
      create(:error_log, breadcrumbs: nil, occurred_at: 1.day.ago)
      result = described_class.call(30)
      expect(result[:events]).to eq([])
    end

    it "returns empty events when no rack_attack breadcrumbs exist" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(sql_crumb("SELECT 1")),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:events]).to eq([])
    end

    it "extracts rack_attack events from breadcrumbs" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          rack_attack_crumb(rule: "login/ip", type: "throttle", discriminator: "192.168.1.1", path: "/login")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:events].size).to eq(1)

      event = result[:events].first
      expect(event[:rule]).to eq("login/ip")
      expect(event[:match_type]).to eq("throttle")
      expect(event[:count]).to eq(1)
      expect(event[:unique_ips]).to eq(1)
      expect(event[:ips]).to include("192.168.1.1")
    end

    it "groups events by rule name" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          rack_attack_crumb(rule: "login/ip", discriminator: "1.1.1.1"),
          rack_attack_crumb(rule: "login/ip", discriminator: "2.2.2.2"),
          rack_attack_crumb(rule: "api/ip", discriminator: "3.3.3.3")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:events].size).to eq(2)

      login_rule = result[:events].find { |e| e[:rule] == "login/ip" }
      expect(login_rule[:count]).to eq(2)
      expect(login_rule[:unique_ips]).to eq(2)
    end

    it "aggregates across multiple errors" do
      2.times do |i|
        create(:error_log,
          breadcrumbs: breadcrumbs_json(
            rack_attack_crumb(rule: "login/ip", discriminator: "10.0.0.#{i + 1}")
          ),
          occurred_at: 1.day.ago)
      end

      result = described_class.call(30)
      expect(result[:events].size).to eq(1)

      event = result[:events].first
      expect(event[:count]).to eq(2)
      expect(event[:unique_ips]).to eq(2)
      expect(event[:error_count]).to eq(2)
    end

    it "sorts by count descending" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          rack_attack_crumb(rule: "rare_rule"),
          rack_attack_crumb(rule: "common_rule"),
          rack_attack_crumb(rule: "common_rule"),
          rack_attack_crumb(rule: "common_rule")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      rules = result[:events].map { |e| e[:rule] }
      expect(rules).to eq([ "common_rule", "rare_rule" ])
    end

    it "respects time range" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(rack_attack_crumb(rule: "old_rule")),
        occurred_at: 40.days.ago)

      create(:error_log,
        breadcrumbs: breadcrumbs_json(rack_attack_crumb(rule: "recent_rule")),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:events].size).to eq(1)
      expect(result[:events].first[:rule]).to eq("recent_rule")
    end

    it "filters by application_id" do
      app1 = create(:application, name: "App1")
      app2 = create(:application, name: "App2")

      create(:error_log,
        application: app1,
        breadcrumbs: breadcrumbs_json(rack_attack_crumb(rule: "rule_a")),
        occurred_at: 1.day.ago)

      create(:error_log,
        application: app2,
        breadcrumbs: breadcrumbs_json(rack_attack_crumb(rule: "rule_b")),
        occurred_at: 1.day.ago)

      result = described_class.call(30, application_id: app1.id)
      expect(result[:events].size).to eq(1)
      expect(result[:events].first[:rule]).to eq("rule_a")
    end

    it "handles malformed JSON breadcrumbs gracefully" do
      create(:error_log,
        breadcrumbs: "not valid json {{{",
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:events]).to eq([])
    end

    it "deduplicates error_ids" do
      error = create(:error_log,
        breadcrumbs: breadcrumbs_json(
          rack_attack_crumb(rule: "login/ip", discriminator: "1.1.1.1"),
          rack_attack_crumb(rule: "login/ip", discriminator: "1.1.1.1")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      event = result[:events].first
      expect(event[:error_ids]).to eq([ error.id ])
      expect(event[:error_count]).to eq(1)
    end

    it "tracks last_seen as the most recent error occurred_at" do
      freeze_time do
        create(:error_log,
          breadcrumbs: breadcrumbs_json(rack_attack_crumb(rule: "test")),
          occurred_at: 5.days.ago)

        create(:error_log,
          breadcrumbs: breadcrumbs_json(rack_attack_crumb(rule: "test")),
          occurred_at: 1.day.ago)

        result = described_class.call(30)
        expect(result[:events].first[:last_seen]).to eq(1.day.ago)
      end
    end

    it "tracks unique IPs via Set" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          rack_attack_crumb(rule: "login/ip", discriminator: "1.1.1.1"),
          rack_attack_crumb(rule: "login/ip", discriminator: "1.1.1.1"),
          rack_attack_crumb(rule: "login/ip", discriminator: "2.2.2.2")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      event = result[:events].first
      expect(event[:unique_ips]).to eq(2)
    end

    it "captures different match types" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          rack_attack_crumb(rule: "block_rule", type: "blocklist"),
          rack_attack_crumb(rule: "track_rule", type: "track")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      types = result[:events].map { |e| e[:match_type] }
      expect(types).to contain_exactly("blocklist", "track")
    end

    it "handles breadcrumbs with missing meta hash" do
      create(:error_log,
        breadcrumbs: [ { "c" => "rack_attack", "m" => "throttle: unknown" } ].to_json,
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:events].size).to eq(1)
      expect(result[:events].first[:rule]).to eq("unknown")
    end

    it "handles breadcrumbs with empty discriminator" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          rack_attack_crumb(rule: "test_rule", discriminator: "")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      event = result[:events].first
      expect(event[:unique_ips]).to eq(0)
      expect(event[:ips]).to eq([])
    end

    it "handles large number of events without error" do
      crumbs = 100.times.map { |i| rack_attack_crumb(rule: "rule_#{i % 5}", discriminator: "10.0.0.#{i}") }
      create(:error_log,
        breadcrumbs: breadcrumbs_json(*crumbs),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:events].size).to eq(5)
      expect(result[:events].sum { |e| e[:count] }).to eq(100)
    end
  end
end
