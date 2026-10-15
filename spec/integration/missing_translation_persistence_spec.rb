# frozen_string_literal: true

require "rails_helper"

# End to end: a host I18n lookup that misses reaches the database with no
# error raised anywhere, through the same executor hook the engine registers.
#
# The unit specs assert on the in-memory buffer; this one exists so the
# feature cannot pass its suite while never actually writing a row (the
# lesson of Rack Attack tracking, issue #143).
RSpec.describe "Missing translation persistence", type: :request do
  let(:handler) { RailsErrorDashboard::Services::MissingTranslationHandler }
  let(:tracker) { RailsErrorDashboard::Services::MissingTranslationTracker }
  let(:model) { RailsErrorDashboard::MissingTranslation }

  around do |example|
    original = I18n.exception_handler
    RailsErrorDashboard.configuration.enable_missing_translation_tracking = true
    tracker.reset!
    handler.install!
    example.run
  ensure
    handler.uninstall!
    I18n.exception_handler = original
    tracker.reset!
    RailsErrorDashboard.reset_configuration!
  end

  it "writes a miss out when the unit of work completes and the interval has passed" do
    3.times { I18n.t("orders.summary.total", locale: :en) }
    I18n.t("orders.summary.total", locale: :"pt-BR")

    # Nothing is written on the request path itself.
    expect(model.count).to eq(0)

    # What the engine registers on Rails.application.executor.to_complete.
    tracker.deadline -= tracker::FLUSH_INTERVAL
    tracker.flush_if_due!

    rows = model.order(:locale).to_a
    expect(rows.map { |r| [ r.locale, r.translation_key, r.miss_count ] })
      .to eq([ [ "en", "orders.summary.total", 3 ], [ "pt-BR", "orders.summary.total", 1 ] ])
    expect(rows.first.source).to match(/missing_translation_persistence_spec\.rb:\d+\z/)
  end

  it "does not write before the interval, so a flood is one write per interval" do
    I18n.t("orders.summary.total", locale: :en)

    tracker.flush_if_due!

    expect(model.count).to eq(0)
    expect(tracker.buffered_counts.size).to eq(1)
  end

  it "then shows the key on the dashboard page" do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    I18n.t("orders.summary.total", locale: :en)
    tracker.flush!

    get "/error_dashboard/errors/missing_translations"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("orders.summary.total")
  end

  it "survives the table not being migrated yet without raising or losing the host's result" do
    allow(model).to receive(:table_exists?).and_return(false)

    result = I18n.t("orders.summary.total", locale: :en)
    expect(result).to eq("Translation missing: en.orders.summary.total")

    expect { tracker.flush! }.not_to raise_error
  end
end
