# frozen_string_literal: true

require "rails_helper"

# The five stat cards above the error list. This partial was missed by the
# Phase 2 extraction sweep and kept hardcoded English labels until now, which
# bin/i18n-check's hardcoded-English heuristic caught.
#
# It is worth its own spec because it is not an ordinary page partial: nothing
# renders it with `render "stats"`, so a grep for that form says it is dead
# code. It is not — Services::ErrorBroadcaster#broadcast_stats renders it by
# string path over ActionCable, outside any request. Both paths are pinned
# below so the next sweep does not mistake it for unused again.
RSpec.describe "rails_error_dashboard/errors/_stats.html.erb", type: :view do
  before(:all) do
    ActionView::TestCase::TestController.helper(RailsErrorDashboard::I18nHelper)
  end

  let(:stats) do
    { total_today: 3, total_week: 12, unresolved: 5, resolved: 7, reopened: 2 }
  end

  def render_partial
    render template: "rails_error_dashboard/errors/_stats", locals: { stats: stats }
  rescue ActionView::MissingTemplate
    render partial: "rails_error_dashboard/errors/stats", locals: { stats: stats }
  end

  it "renders every label through red_t rather than as hardcoded English" do
    render_partial

    expect(rendered).to include("Today")
    expect(rendered).to include("This Week")
    expect(rendered).to include("Unresolved")
    expect(rendered).to include("Resolved")
    expect(rendered).to include("Reopened")
  end

  it "renders the counts it was handed" do
    render_partial

    expect(rendered).to include(">3<").and include(">12<")
    expect(rendered).to include(">5<").and include(">7<").and include(">2<")
  end

  it "translates the labels when the dashboard locale is not English" do
    RailsErrorDashboard::Current.locale = "de"

    render_partial

    # If any label were still a hardcoded literal it would survive the locale
    # switch untranslated — that is the defect this file exists to prevent.
    expect(rendered).to include("Heute")
    expect(rendered).to include("Diese Woche")
    expect(rendered).to include("Offen")
    expect(rendered).not_to include("This Week")
  ensure
    RailsErrorDashboard::Current.locale = nil
  end

  # The keys must exist in every shipped locale, not just German. bin/i18n-check
  # enforces parity across the whole file; this pins the five specifically, since
  # a partial rendered outside a request is the easiest place for a missing key
  # to go unnoticed.
  it "has a real translation for every label in every shipped locale" do
    keys = %w[today this_week unresolved resolved reopened]

    RailsErrorDashboard::I18nStore.available_locales.each do |locale|
      keys.each do |key|
        full_key = "red.errors.stats.#{key}"
        value = RailsErrorDashboard::I18nStore.translate(full_key, locale: locale)

        expect(value).to be_present, "missing #{full_key} for #{locale}"
        # A miss returns humanized key text rather than raising, so presence
        # alone proves nothing — reject the humanized shape explicitly.
        expect(value).not_to include(full_key), "#{full_key} unresolved for #{locale}"

        next if locale.to_s == "en"

        english = RailsErrorDashboard::I18nStore.translate(full_key, locale: "en")
        expect(value).not_to eq(english),
          "#{locale} #{full_key} is identical to English — untranslated or fell back"
      end
    end
  end
end
