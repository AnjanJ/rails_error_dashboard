# frozen_string_literal: true

require "rails_helper"

# P4-T2 — mailer templates.
#
# Email is the one surface where a RED translation lands in someone else's mail
# client. Two failure modes matter more here than on the dashboard: HTML
# entities leaking into a plain-text part, and a date rendering in English
# because Ruby's strftime is not locale-aware.
RSpec.describe "Mailer i18n" do
  # A real second locale, written to config/locales so I18nStore loads it the
  # way it loads a shipped one. Deliberately not "zz" — four existing specs use
  # that as their example of an unshipped locale.
  TEST_MAIL_LOCALE = "xm"

  with_locale_fixture TEST_MAIL_LOCALE, <<~YAML
    xm:
      red:
        common:
          severity:
            critical: "KRITISCH-XM"
            high: "HOCH-XM"
            medium: "MITTEL-XM"
            low: "NIEDRIG-XM"
        time:
          formats:
            full: "%d. %B %Y %H:%M"
            date_only: "%d. %B %Y"
        js:
          months:
            - "Januar-XM"
            - "Februar-XM"
            - "Marz-XM"
            - "April-XM"
            - "Mai-XM"
            - "Juni-XM"
            - "Juli-XM"
            - "August-XM"
            - "September-XM"
            - "Oktober-XM"
            - "November-XM"
            - "Dezember-XM"
        mailers:
          shared:
            product_name: "Rails Error Dashboard"
            unknown_application: "Unbekannt-XM"
          error_alert:
            subject: "[%{application}] %{error_type}: %{message}"
            heading: "Fehleralarm-XM"
            labels:
              application: "Anwendung-XM"
              error_type: "Fehlertyp-XM"
              platform: "Plattform-XM"
              occurred_at: "Aufgetreten-XM"
              user_id: "Benutzer-ID-XM"
              ip_address: "IP-Adresse-XM"
              request_url: "Anfrage-URL-XM"
              message: "Nachricht-XM"
              error_id: "Fehler-ID-XM"
            stack_trace:
              one: "Stapel-XM (%{count} Zeile)"
              other: "Stapel-XM (%{count} Zeilen)"
            view_details: "Details-XM"
            view_details_text: "Details im Dashboard-XM:"
            footer: "Automatische Meldung von %{product}. Man kann d'accéder."
          digest:
            subject:
              one: "Digest-XM — %{count} Fehler (%{period})"
              other: "Digest-XM — %{count} Fehler (%{period})"
            heading: "Digest-Uberschrift-XM"
            periods:
              daily: "Letzte 24 Stunden-XM"
              weekly: "Letzte 7 Tage-XM"
  YAML

  let!(:app_record) { create(:application, name: "AcmeApp") }
  let!(:error_log) do
    create(
      :error_log,
      application: app_record,
      error_type: "ActiveRecord::RecordNotFound",
      message: "Couldn't find User with 'id'=42",
      backtrace: (1..15).map { |i| "app/models/user.rb:#{i}:in `find'" }.join("\n")
    )
  end

  def alert(locale:)
    RailsErrorDashboard::ErrorNotificationMailer.error_alert(
      error_log, [ "ops@example.com" ], locale: locale
    )
  end

  def text_of(mail)
    (mail.text_part || mail).body.to_s
  end

  def html_of(mail)
    (mail.html_part || mail).body.to_s
  end

  # The shape DigestBuilder returns. Built here rather than run through the
  # builder because these examples are about the subject line, not the query
  # layer — but it must be complete, since the body template reads :comparison.
  def digest_hash(new_errors:)
    {
      period: :weekly,
      period_label: "Last 7 days",
      generated_at: Time.utc(2026, 8, 18, 14, 30),
      stats: {
        new_errors: new_errors, total_occurrences: new_errors,
        resolved: 0, unresolved: new_errors, critical_high: 0, resolution_rate: 0
      },
      top_errors: [],
      critical_unresolved: [],
      comparison: { current_count: 0, previous_count: 0, error_delta: 0, error_delta_percentage: nil }
    }
  end

  it "ships the fixture locale, so the assertions below can actually fail" do
    expect(RailsErrorDashboard::I18nStore.available?(TEST_MAIL_LOCALE)).to be(true)
  end

  describe "REQ-2 — both formats localized" do
    it "translates the text part" do
      expect(text_of(alert(locale: TEST_MAIL_LOCALE))).to include("Fehleralarm-XM", "Anwendung-XM")
    end

    it "translates the html part" do
      expect(html_of(alert(locale: TEST_MAIL_LOCALE))).to include("Fehleralarm-XM", "Anwendung-XM")
    end

    it "renders English when no locale is passed" do
      expect(text_of(alert(locale: "en"))).to include("Error Alert", "Application")
    end
  end

  describe "the text part must not carry HTML entities" do
    # red_t escapes for HTML. In a text/plain part that lands in the reader's
    # mail client as a literal "&#39;", which is why the text templates use
    # red_mail_t instead. The fixture's footer contains an apostrophe for
    # exactly this assertion.
    it "renders an apostrophe in a translation as an apostrophe" do
      body = text_of(alert(locale: TEST_MAIL_LOCALE))

      expect(body).to include("d'accéder")
      expect(body).not_to include("&#39;")
    end

    it "renders error content verbatim, unescaped" do
      body = text_of(alert(locale: TEST_MAIL_LOCALE))

      expect(body).to include("Couldn't find User with 'id'=42")
      expect(body).not_to include("&#39;")
    end

    it "still escapes in the html part" do
      expect(html_of(alert(locale: TEST_MAIL_LOCALE))).to include("&#39;")
    end
  end

  describe "REQ-7 — dates use the locale's format and month names" do
    # Ruby's strftime always emits English month names, so a mailer that just
    # called strftime would render "August" in every locale.
    it "uses the locale's month names and date order" do
      error_log.update!(occurred_at: Time.utc(2026, 8, 18, 14, 30))

      expect(text_of(alert(locale: TEST_MAIL_LOCALE))).to include("18. August-XM 2026 14:30")
    end

    it "uses English month names and US order for en" do
      error_log.update!(occurred_at: Time.utc(2026, 8, 18, 14, 30))

      expect(text_of(alert(locale: "en"))).to include("August 18, 2026")
    end

    it "never renders a bare strftime directive" do
      expect(text_of(alert(locale: TEST_MAIL_LOCALE))).not_to match(/%[A-Za-z]/)
    end
  end

  describe "REQ-4 — digest period labels are keys" do
    it "translates the daily label" do
      digest = RailsErrorDashboard::Services::DigestBuilder.call(
        period: :daily, locale: TEST_MAIL_LOCALE
      )

      expect(digest[:period_label]).to eq("Letzte 24 Stunden-XM")
    end

    it "translates the weekly label" do
      digest = RailsErrorDashboard::Services::DigestBuilder.call(
        period: :weekly, locale: TEST_MAIL_LOCALE
      )

      expect(digest[:period_label]).to eq("Letzte 7 Tage-XM")
    end

    it "keeps the English labels for en" do
      expect(
        RailsErrorDashboard::Services::DigestBuilder.call(period: :daily, locale: "en")[:period_label]
      ).to eq("Last 24 hours")
    end
  end

  describe "REQ-1 — subjects" do
    it "pluralizes the digest subject" do
      subjects = [ 1, 5 ].map do |count|
        RailsErrorDashboard::DigestMailer.digest_summary(
          digest_hash(new_errors: count), [ "a@b.com" ], locale: "en"
        ).subject
      end

      expect(subjects).to eq(
        [ "RED Digest — 1 new error (Last 7 days)",
          "RED Digest — 5 new errors (Last 7 days)" ]
      )
    end

    it "localizes the alert subject while leaving error content verbatim" do
      subject = alert(locale: TEST_MAIL_LOCALE).subject

      expect(subject).to include("AcmeApp")
      expect(subject).to include("ActiveRecord::RecordNotFound")
      # This fixture's subject key deliberately omits the emoji, proving a
      # locale can drop it rather than having it hardcoded around the key.
      expect(subject).not_to include("🚨")
    end

    it "REQ-5 — preserves the emoji in the English subject" do
      expect(alert(locale: "en").subject).to start_with("🚨")
    end

    it "falls back to the unknown-application label" do
      # application is NOT NULL in the schema, but error_log.application can
      # still be nil in memory when the association is not loaded or the row
      # was deleted underneath. The subject must not render "nil" there.
      allow(error_log).to receive(:application).and_return(nil)

      expect(alert(locale: TEST_MAIL_LOCALE).subject).to include("Unbekannt-XM")
    end
  end

  describe "REQ-6 — error content is never translated" do
    it "leaves the exception class, message and backtrace verbatim" do
      body = text_of(alert(locale: TEST_MAIL_LOCALE))

      expect(body).to include("ActiveRecord::RecordNotFound")
      expect(body).to include("Couldn't find User with 'id'=42")
      expect(body).to include("app/models/user.rb:1:in `find'")
    end

    it "shows only the first 10 backtrace lines, and says so" do
      body = text_of(alert(locale: "en"))

      expect(body).to include("Stack Trace (first 10 lines)")
      expect(body).to include("app/models/user.rb:10:in `find'")
      expect(body).not_to include("app/models/user.rb:11:in `find'")
    end
  end

  describe "REQ-3 — the text layout survives long translations" do
    it "keeps every line within 80 columns" do
      # Labels are no longer padded to a column, so a translation twice the
      # English length cannot push a line past the fold. URLs and backtrace
      # frames are content, not layout, and are exempt.
      overlong = text_of(alert(locale: TEST_MAIL_LOCALE)).lines.reject do |line|
        line.include?("http") || line.include?("app/models/") || line.include?("::")
      end.select { |line| line.chomp.length > 80 }

      expect(overlong).to be_empty
    end
  end

  describe "nothing in the mail path raises" do
    it "renders with a locale RED does not ship" do
      expect { text_of(alert(locale: "zz")) }.not_to raise_error
    end

    it "renders a nil timestamp as empty rather than raising" do
      # occurred_at is NOT NULL in the schema, so this exercises the helper
      # directly — red_mail_time must be total for any caller.
      view = Object.new
      view.extend(RailsErrorDashboard::MailerI18nHelper)

      expect(view.red_mail_time(nil)).to eq("")
    end

    it "renders with no backtrace" do
      error_log.update!(backtrace: nil)

      expect { text_of(alert(locale: TEST_MAIL_LOCALE)) }.not_to raise_error
    end
  end
end
