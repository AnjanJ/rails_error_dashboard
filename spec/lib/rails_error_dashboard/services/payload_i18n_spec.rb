# frozen_string_literal: true

require "rails_helper"

# P4-T3 — notification payload builders.
#
# The rule here is narrower than anywhere else in the sprint: only values a
# HUMAN reads get translated. Anything a receiving system parses stays English,
# because translating it breaks the integration rather than localizing it.
# Half these examples exist to hold that line.
RSpec.describe "Notification payload i18n" do
  PAYLOAD_LOCALE = "xp"

  with_locale_fixture PAYLOAD_LOCALE, probe: "red.notifications.error_alert.view_details", yaml: <<~YAML
    xp:
      red:
        notifications:
          shared:
            product_name: "Rails Error Dashboard"
            unknown: "Unbekannt-XP"
            not_available: "K.A.-XP"
          error_alert:
            fallback: "Fehlermeldung-XP"
            heading: "Fehleralarm-XP"
            discord_title: "Neuer Fehler-XP: %{error_type}"
            pagerduty_summary: "[%{application}] Kritisch-XP: %{error_type} in %{platform}"
            labels:
              application: "Anwendung-XP"
              error_type: "Fehlertyp-XP"
              platform: "Plattform-XP"
              occurred: "Aufgetreten-XP"
              message: "Nachricht-XP"
              user: "Benutzer-XP"
              ip_address: "IP-XP"
              request_url: "URL-XP"
              occurrences: "Vorkommen-XP"
              controller: "Controller-XP"
              action: "Aktion-XP"
              first_seen: "Zuerst-XP"
              location: "Ort-XP"
            user_fallback: "Benutzer-XP #%{id}"
            view_details: "Details-XP"
            view_in_dashboard: "Im Dashboard-XP"
            error_id: "Fehler-ID-XP: %{id}"
          baseline_alert:
            fallback: "Abweichung-XP"
            heading: "Abweichung erkannt-XP"
            labels:
              severity: "Schwere-XP"
              std_devs: "Abweichungen-XP"
              threshold: "Schwelle-XP"
              baseline_type: "Basistyp-XP"
              baseline_info: "Basisinfo-XP"
            level:
              critical: "KRITISCH-XP"
              high: "HOCH-XP"
              elevated: "ERHOEHT-XP"
              unknown: "UNBEKANNT-XP"
            std_devs_above: "%{value}σ ueber Basis-XP"
            threshold_errors:
              one: "%{value} Fehler-XP"
              other: "%{value} Fehler-XP"
            view_in_dashboard: "Im Dashboard-XP"
  YAML

  let!(:app_record) { create(:application, name: "AcmeApp") }
  let!(:error_log) do
    create(
      :error_log,
      application: app_record,
      error_type: "ActiveRecord::RecordNotFound",
      message: "Couldn't find User",
      platform: "production",
      controller_name: "UsersController",
      action_name: "show"
    )
  end

  def json(payload)
    JSON.parse(payload.to_json)
  end

  describe "Slack" do
    subject(:payload) do
      RailsErrorDashboard::Services::SlackPayloadBuilder.call(error_log, locale: PAYLOAD_LOCALE)
    end

    it "localizes the fallback text, heading and button" do
      flat = payload.to_json

      expect(payload[:text]).to eq("Fehlermeldung-XP")
      expect(flat).to include("Fehleralarm-XP", "Anwendung-XP", "Details-XP")
    end

    it "REQ-2 — leaves Block Kit vocabulary in English" do
      types = json(payload)["blocks"].map { |b| b["type"] }

      expect(types).to include("header", "section", "actions", "context")
      expect(payload.to_json).to include('"style":"primary"')
    end

    it "REQ-6 — leaves error content verbatim" do
      expect(payload.to_json).to include("ActiveRecord::RecordNotFound")
    end

    it "renders English for the default locale" do
      english = RailsErrorDashboard::Services::SlackPayloadBuilder.call(error_log)

      expect(english[:text]).to eq("🚨 New Error Alert")
      expect(english.to_json).to include("Application", "View Details")
    end
  end

  describe "Discord" do
    subject(:payload) do
      RailsErrorDashboard::Services::DiscordPayloadBuilder.call(error_log, locale: PAYLOAD_LOCALE)
    end

    it "localizes the title and field names" do
      embed = payload[:embeds].first

      expect(embed[:title]).to eq("Neuer Fehler-XP: ActiveRecord::RecordNotFound")
      expect(embed[:fields].map { |f| f[:name] }).to include("Anwendung-XP", "Vorkommen-XP", "Ort-XP")
    end

    it "REQ-2 — leaves embed schema untouched" do
      embed = json(payload)["embeds"].first

      expect(embed).to have_key("color")
      expect(embed).to have_key("timestamp")
      expect(embed["fields"].map { |f| f["inline"] }).to all(be_in([ true, false ]))
    end

    it "keeps the product name untranslated in the footer" do
      expect(payload[:embeds].first[:footer][:text]).to eq("Rails Error Dashboard")
    end
  end

  describe "PagerDuty" do
    subject(:payload) do
      RailsErrorDashboard::Services::PagerdutyPayloadBuilder.call(
        error_log, routing_key: "rk", locale: PAYLOAD_LOCALE
      )
    end

    it "localizes only the summary and the link text" do
      expect(payload[:payload][:summary]).to start_with("[AcmeApp] Kritisch-XP:")
      expect(payload[:links].first[:text]).to eq("Im Dashboard-XP")
    end

    # These are the ones that would actually break PagerDuty rather than merely
    # look untranslated: both are API enums with a fixed vocabulary.
    it "REQ-2 — never translates event_action or severity" do
      expect(payload[:event_action]).to eq("trigger")
      expect(payload[:payload][:severity]).to eq("critical")
    end

    it "REQ-2 — keeps custom_details keys in English" do
      keys = json(payload)["payload"]["custom_details"].keys

      expect(keys).to include(
        "application", "message", "controller", "action", "platform",
        "occurrences", "first_seen_at", "last_seen_at", "request_url",
        "backtrace", "error_id"
      )
    end
  end

  describe "Webhook" do
    # REQ-6: the schema AND the values are an API contract. This payload has no
    # human-readable chrome, so a translated locale must produce byte-identical
    # output to English.
    it "is byte-identical in every locale" do
      english = RailsErrorDashboard::Services::WebhookPayloadBuilder.call(error_log)
      translated = RailsErrorDashboard::Services::WebhookPayloadBuilder.call(
        error_log, locale: PAYLOAD_LOCALE
      )

      # :timestamp is Time.current and differs between calls by construction.
      expect(translated.except(:timestamp)).to eq(english.except(:timestamp))
    end
  end

  describe "Baseline alert" do
    let(:anomaly) do
      { level: :critical, std_devs_above: 3.25, threshold: 12.5, baseline_type: "rolling_7d" }
    end

    it "localizes Slack labels and the anomaly level" do
      flat = RailsErrorDashboard::Services::BaselineAlertPayloadBuilder
        .slack_payload(error_log, anomaly, locale: PAYLOAD_LOCALE).to_json

      expect(flat).to include("Abweichung erkannt-XP", "Schwere-XP", "KRITISCH-XP")
    end

    it "renders the anomaly level from a key rather than upcasing the symbol" do
      flat = RailsErrorDashboard::Services::BaselineAlertPayloadBuilder
        .discord_payload(error_log, anomaly, locale: PAYLOAD_LOCALE).to_json

      expect(flat).to include("KRITISCH-XP")
      expect(flat).not_to include("CRITICAL")
    end

    it "falls back to an unknown level rather than rendering a bare symbol" do
      flat = RailsErrorDashboard::Services::BaselineAlertPayloadBuilder
        .discord_payload(error_log, anomaly.merge(level: :something_new), locale: PAYLOAD_LOCALE).to_json

      expect(flat).to include("UNBEKANNT-XP")
    end

    it "keeps the webhook variant machine-readable" do
      payload = RailsErrorDashboard::Services::BaselineAlertPayloadBuilder
        .webhook_payload(error_log, anomaly, locale: PAYLOAD_LOCALE)

      expect(payload[:event]).to eq("baseline_anomaly")
      expect(payload[:anomaly][:level]).to eq("critical")
    end
  end

  describe "nothing in the payload path raises" do
    it "builds every payload for a locale RED does not ship" do
      expect {
        RailsErrorDashboard::Services::SlackPayloadBuilder.call(error_log, locale: "zz")
        RailsErrorDashboard::Services::DiscordPayloadBuilder.call(error_log, locale: "zz")
        RailsErrorDashboard::Services::WebhookPayloadBuilder.call(error_log, locale: "zz")
        RailsErrorDashboard::Services::PagerdutyPayloadBuilder.call(error_log, routing_key: "k", locale: "zz")
      }.not_to raise_error
    end
  end
end
