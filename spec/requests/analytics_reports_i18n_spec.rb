# frozen_string_literal: true

require "rails_helper"

# The five analytics/reports pages (analytics, correlation, platform_comparison,
# releases, user_impact — P2-T6). Existing specs already pin most of the
# rendered strings byte-for-byte (extraction preserved the English text
# verbatim), so this spec focuses on what those specs don't cover: the
# machine-value lookups that replaced .capitalize/.gsub calls (stability,
# trend, severity), pluralized counts, the shared days_filter key now used
# across pages, and the XSS-safe content_tag markup in the empty states.
RSpec.describe "Analytics & reports translations", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    RailsErrorDashboard.configuration.enable_error_correlation = true
    RailsErrorDashboard.configuration.enable_platform_comparison = true
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_error_correlation = false
    RailsErrorDashboard.configuration.enable_platform_comparison = false
  end

  describe "shared days_filter key" do
    it "renders the same day-range labels used on health pages" do
      get "/error_dashboard/errors/correlation", params: { days: 30 }
      expect(response.body).to include("7 Days").and include("30 Days").and include("90 Days")
    end

    it "renders the 14-day option unique to platform_comparison" do
      get "/error_dashboard/errors/platform_comparison", params: { days: 14 }
      expect(response.body).to include("14 Days")
    end
  end

  describe "analytics — days_pill key lookup" do
    it "renders the compact pill labels via a key lookup, not a hardcoded label array" do
      get "/error_dashboard/errors/analytics"

      expect(response.body).to include("7d").and include("14d").and include("30d")
        .and include("60d").and include("90d")
    end
  end

  describe "releases — stability value-to-key lookup" do
    # The static footer legend spells out "Green"/"Yellow"/"Red" unconditionally
    # regardless of any release's actual stability, so a plain include("Green")
    # would pass even if the badge lookup itself were reverted to the raw
    # symbol. Scope to the "Current Release" card's badge specifically —
    # the only card on the page with a border-primary class — to pin the
    # actual value-to-key lookup, not the always-present legend text.
    def current_release_badge_text(body)
      # .card-header also has a "Live" badge; the stability badge lives in
      # .card-body, so scope past the header to avoid matching the wrong one.
      Nokogiri::HTML.fragment(body).at_css(".card.border-primary .card-body .badge")&.text&.strip
    end

    it "shows Green for a release at or below the average error rate" do
      create(:error_log, :with_version, application: application, app_version: "1.0.0",
        occurred_at: 1.day.ago)

      get "/error_dashboard/errors/releases"

      expect(current_release_badge_text(response.body)).to eq("Green")
    end

    it "shows Red for a release with more than 2x the average error rate" do
      # stability_indicator(count, avg) compares each release's count against
      # the average across ALL releases, so two releases alone can never push
      # the larger one's ratio past 2x (avg is pulled up by its own count).
      # Two small releases pull the average down; the third, current release
      # then lands far enough above it to cross the :red threshold.
      create(:error_log, :with_version, application: application, app_version: "1.0.0",
        occurred_at: 20.days.ago)
      create(:error_log, :with_version, application: application, app_version: "2.0.0",
        occurred_at: 10.days.ago)
      12.times do
        create(:error_log, :with_version, application: application, app_version: "3.0.0",
          occurred_at: 1.day.ago)
      end

      get "/error_dashboard/errors/releases"

      expect(current_release_badge_text(response.body)).to eq("Red")
    end
  end

  describe "correlation — trend direction value-to-key lookup" do
    it "renders a humanized trend phrase, not a raw underscored symbol" do
      # Errors concentrated in the current 7-day window vs. none in the
      # previous window drives change_percentage > 20 => :increasing_significantly.
      7.times { |i| create(:error_log, application: application, occurred_at: i.hours.ago) }

      get "/error_dashboard/errors/correlation", params: { days: 7 }

      expect(response.body).not_to include("increasing_significantly")
      expect(response.body).to include("increasing significantly")
    end
  end

  describe "correlation — correlation_strength value-to-key lookup" do
    it "renders the Strong/Moderate/Weak badge text for time-correlated pairs" do
      # Two error types occurring at the exact same hours across several days
      # produce a high (:strong) time correlation.
      5.times do |i|
        ts = i.days.ago.change(hour: 10)
        create(:error_log, application: application, error_type: "ErrorA", occurred_at: ts)
        create(:error_log, application: application, error_type: "ErrorB", occurred_at: ts)
      end

      get "/error_dashboard/errors/correlation", params: { days: 30 }

      expect(response.body).to match(/Strong|Moderate|Weak/)
    end
  end

  describe "user_impact — severity lookup instead of .capitalize" do
    it "looks up the severity through red.common.severity, not sev.capitalize" do
      create(:error_log, :with_user, application: application, error_type: "FatalError")
      allow_any_instance_of(RailsErrorDashboard::ErrorLog).to receive(:severity).and_return(:critical)

      # "Critical".capitalize == "Critical", so a plain substring match on the
      # rendered page would pass even with the .capitalize call reinstated.
      # Assert the actual lookup path is exercised instead.
      allow(RailsErrorDashboard::I18nStore).to receive(:translate).and_call_original
      expect(RailsErrorDashboard::I18nStore).to receive(:translate)
        .with("red.common.severity.critical", hash_including(default: "critical")).and_call_original

      get "/error_dashboard/errors/user_impact"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "analytics MTTR table — severity lookup instead of .capitalize" do
    it "looks up the severity through red.common.severity, not severity.to_s.capitalize" do
      # error_type: "StandardError" isn't in any custom/critical/high/medium
      # list, so SeverityClassifier falls back to :low.
      create(:error_log, :resolved, application: application, occurred_at: 2.days.ago)

      allow(RailsErrorDashboard::I18nStore).to receive(:translate).and_call_original
      expect(RailsErrorDashboard::I18nStore).to receive(:translate)
        .with("red.common.severity.low", hash_including(default: "low")).and_call_original

      get "/error_dashboard/errors/analytics"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "analytics — pluralized release comparison badges" do
    it "pluralizes the latest-release error count correctly at 1 and at N" do
      create(:error_log, :with_version, application: application, app_version: "1.0.0",
        occurred_at: 10.days.ago)
      create(:error_log, :with_version, application: application, app_version: "2.0.0",
        occurred_at: 1.day.ago)

      get "/error_dashboard/errors/analytics"

      expect(response.body).to match(/\d+ errors?\b/)
    end
  end

  describe "user_impact — pluralized user/occurrence counts" do
    it "pluralizes 'users' and renders the 'Nx' occurrence badge" do
      create(:error_log, application: application, error_type: "SharedError", user_id: 1)
      create(:error_log, application: application, error_type: "SharedError", user_id: 2)

      get "/error_dashboard/errors/user_impact"

      expect(response.body).to match(/\d+ users?\b/)
      expect(response.body).to match(/\d+x/)
    end
  end

  describe "releases — safe markup in the empty-state instructions" do
    it "wraps config option names in <code> via content_tag, not raw interpolation" do
      get "/error_dashboard/errors/releases"

      expect(response.body).to include("<code>config.app_version</code>")
      expect(response.body).to include("<code>APP_VERSION</code>")
    end
  end

  describe "user_impact — safe markup in the empty-state instructions" do
    it "wraps attribute names in <code> via content_tag, not raw interpolation" do
      get "/error_dashboard/errors/user_impact"

      expect(response.body).to include("<code>user_id</code>")
      expect(response.body).to include("<code>CurrentAttributes</code>")
    end
  end

  describe "platform_comparison — translated health status badges" do
    # stability_score is normalized against the platform with the MOST
    # errors present (error_score = 1.0 - count/max_count), so a single lone
    # platform always normalizes to error_score 0 (it IS the max) and never
    # reads :healthy. A second, much noisier platform is required to give the
    # quiet platform's error_score room to approach 1.0.
    it "renders the translated Healthy badge for the quieter of two platforms" do
      create(:error_log, application: application, platform: "iOS", occurred_at: 1.day.ago)
      20.times do
        create(:error_log, application: application, platform: "Android", occurred_at: 1.day.ago)
      end

      get "/error_dashboard/errors/platform_comparison"

      badges = Nokogiri::HTML.fragment(response.body).css(".card-title .badge").map { |b| b.text.strip }
      expect(badges).to include("Healthy")
    end
  end
end
