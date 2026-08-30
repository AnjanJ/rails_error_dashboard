# frozen_string_literal: true

require "rails_helper"

# #178. Almost every timestamp on the dashboard ships as a <span data-format>
# that formatDateTime() localizes in the browser. Chart labels cannot: they are
# serialized into a JS array and handed to Chart.js as plain strings, so
# whatever the server writes is what the axis shows.
#
# Calling strftime directly there is what put English month names on every
# locale's charts, because Ruby's strftime is not locale-aware. red_chart_date
# routes through the same LocalizedTimeFormatter the mailers and the
# Slack/Discord payloads use, so an axis and an email agree about a date.
RSpec.describe "red_chart_date", type: :helper do
  # A bare object with the helper mixed in — the method only needs red_locale,
  # which comes from I18nHelper itself.
  let(:view_context) do
    Class.new do
      include RailsErrorDashboard::I18nHelper
    end.new
  end

  around do |example|
    original = RailsErrorDashboard.configuration.dashboard_locale
    example.run
  ensure
    RailsErrorDashboard.configuration.dashboard_locale = original
    RailsErrorDashboard::Current.locale = nil
  end

  def with_locale(locale)
    RailsErrorDashboard.configuration.dashboard_locale = locale
    RailsErrorDashboard::Current.locale = locale
    yield
  end

  it "renders English month names in the source locale" do
    with_locale("en") do
      expect(view_context.red_chart_date(Time.utc(2026, 8, 6), "%b %d")).to eq("Aug 06")
    end
  end

  # The bug gmarziou reported: "Aug 6" on a French dashboard.
  #
  # Asserted against a literal, not against LocalizedTimeFormatter's own output
  # for the same pattern. That earlier form was tautological — it restated the
  # implementation, so it passed just as happily when French read "août 06".
  it "renders a localized month name rather than the English one" do
    with_locale("fr") do
      result = view_context.red_chart_date(Time.utc(2026, 8, 6), "%b %d")

      expect(result).to eq("août 06")
    end
  end

  # #178 round 2. The default pattern comes from the locale, so the words AND
  # their order are the locale's own: French puts the day first, German adds
  # the ordinal dot, and ja/zh-CN are year-month-day with CJK separators. Every
  # caller used to hardcode "%b %d", which is US ordering, so ten of eleven
  # locales rendered a correctly-translated month in the wrong place.
  {
    "en" => "Aug 6",
    "fr" => "6 août",
    "de" => "6. Aug.",
    "es" => "6 ago",
    "it" => "6 ago",
    "pt-BR" => "6 ago",
    "pl" => "6 sie",
    "ru" => "6 авг.",
    "uk" => "6 серп.",
    "ja" => "8月6日",
    "zh-CN" => "8月6日"
  }.each do |locale, expected|
    it "orders the default chart date the way #{locale} writes it" do
      with_locale(locale) do
        expect(view_context.red_chart_date(Time.utc(2026, 8, 6))).to eq(expected)
      end
    end
  end

  # Every shipped locale routes through its own dictionary rather than Ruby's.
  # Asserting "differs from English" would be wrong: German for August really
  # is "August", and roughly a hundred values per locale are legitimate
  # cognates. So compare against each locale's own months array instead.
  it "takes the month name from each locale's own dictionary" do
    %w[en de es fr it ja pl pt-BR ru uk zh-CN].each do |locale|
      expected = RailsErrorDashboard::Services::LocalizedTimeFormatter.call(
        Time.utc(2026, 8, 6), pattern: "%B", locale: locale
      )

      with_locale(locale) do
        expect(view_context.red_chart_date(Time.utc(2026, 8, 6), "%B")).to eq(expected),
          "#{locale} did not render its own August"
      end
    end

    # Guard against the above passing vacuously if the formatter ever stopped
    # localizing: at least one locale must differ from English.
    english = RailsErrorDashboard::Services::LocalizedTimeFormatter.call(
      Time.utc(2026, 8, 6), pattern: "%B", locale: "en"
    )
    french = RailsErrorDashboard::Services::LocalizedTimeFormatter.call(
      Time.utc(2026, 8, 6), pattern: "%B", locale: "fr"
    )
    expect(french).not_to eq(english)
  end

  it "accepts a Date as well as a Time, since group_by_day yields Dates" do
    with_locale("en") do
      expect(view_context.red_chart_date(Date.new(2026, 8, 6), "%b %d")).to eq("Aug 06")
    end
  end

  # An axis label must never read "undefined", and a chart must never be the
  # reason a page fails to render.
  it "returns an empty string for nil rather than raising" do
    with_locale("fr") do
      expect(view_context.red_chart_date(nil, "%b %d")).to eq("")
    end
  end

  it "falls back to strftime rather than raising when the formatter fails" do
    allow(RailsErrorDashboard::Services::LocalizedTimeFormatter)
      .to receive(:call).and_raise(StandardError, "boom")

    with_locale("fr") do
      expect(view_context.red_chart_date(Time.utc(2026, 8, 6), "%b %d")).to eq("Aug 06")
    end
  end
end
