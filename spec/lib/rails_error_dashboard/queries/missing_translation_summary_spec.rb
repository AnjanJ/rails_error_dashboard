# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::MissingTranslationSummary do
  let(:model) { RailsErrorDashboard::MissingTranslation }

  def create_row(locale: "en", key: "users.show.greeting", count: 1, source: nil, seen: 1.day.ago, app: nil)
    model.create!(locale: locale, translation_key: key, miss_count: count, source: source,
                  first_seen_at: seen - 1.hour, last_seen_at: seen, application: app)
  end

  it "returns entries most-missed first with the fields the page shows" do
    create_row(key: "a", count: 2, source: "app/views/a.html.erb:1")
    create_row(key: "b", count: 9)
    create_row(key: "c", count: 5, locale: "fr")

    result = described_class.call(30)

    expect(result[:entries].map { |e| e[:key] }).to eq([ "b", "c", "a" ])
    expect(result[:entries].first).to include(locale: "en", key: "b", count: 9, source: nil)
    expect(result[:entries].last[:source]).to eq("app/views/a.html.erb:1")
    expect(result[:entries].first[:first_seen]).to be_a(Time)
    expect(result[:locales]).to eq([ "en", "fr" ])
    expect(result[:overflow_count]).to eq(0)
  end

  it "keeps the same key in two locales as two entries" do
    create_row(locale: "en", key: "k")
    create_row(locale: "de", key: "k")

    expect(described_class.call(30)[:entries].size).to eq(2)
  end

  it "merges duplicate rows for one (locale, key) into a single entry" do
    # Two rows exist when two threads first saw a key at once with no
    # application configured (a NULL application_id passes the unique index).
    create_row(key: "k", count: 2, source: nil, seen: 3.days.ago)
    create_row(key: "k", count: 5, source: "late.rb:1", seen: 1.day.ago)

    entries = described_class.call(30)[:entries]

    expect(entries.size).to eq(1)
    expect(entries.first).to include(key: "k", count: 7, source: "late.rb:1")
    expect(entries.first[:first_seen]).to be_within(2.seconds).of(3.days.ago - 1.hour)
    expect(entries.first[:last_seen]).to be_within(2.seconds).of(1.day.ago)
  end

  it "only includes rows last seen inside the window" do
    create_row(key: "old", seen: 40.days.ago)
    create_row(key: "recent", seen: 2.days.ago)

    expect(described_class.call(30)[:entries].map { |e| e[:key] }).to eq([ "recent" ])
    expect(described_class.call(90)[:entries].size).to eq(2)
  end

  it "reports the overflow count separately and leaves it out of the listing" do
    create_row(key: "k", count: 1)
    create_row(locale: model::OVERFLOW_LOCALE, key: model::OVERFLOW_KEY, count: 7)

    result = described_class.call(30)

    expect(result[:entries].map { |e| e[:key] }).to eq([ "k" ])
    expect(result[:overflow_count]).to eq(7)
    expect(result[:locales]).to eq([ "en" ])
  end

  it "filters by application" do
    shop = create(:application, name: "Shop")
    create_row(key: "shop.k", app: shop)
    create_row(key: "other.k")

    expect(described_class.call(30, application_id: shop.id)[:entries].map { |e| e[:key] }).to eq([ "shop.k" ])
  end

  it "returns an empty result without the table" do
    allow(model).to receive(:table_exists?).and_return(false)

    expect(described_class.call(30)).to eq(entries: [], overflow_count: 0, locales: [])
  end

  it "returns an empty result rather than raising" do
    allow(model).to receive(:seen_since).and_raise(ActiveRecord::StatementInvalid, "boom")

    expect(described_class.call(30)).to eq(entries: [], overflow_count: 0, locales: [])
  end
end
