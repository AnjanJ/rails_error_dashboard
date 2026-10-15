# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::FlushMissingTranslations do
  let(:model) { RailsErrorDashboard::MissingTranslation }
  let(:sep) { RailsErrorDashboard::Services::MissingTranslationTracker::KEY_SEPARATOR }

  after { RailsErrorDashboard.reset_configuration! }

  def key(locale, translation_key)
    "#{locale}#{sep}#{translation_key}"
  end

  it "creates a row per (locale, key) with the count and first source" do
    described_class.call(counts: {
      key("en", "users.show.greeting") => [ 3, "app/views/users/show.html.erb:12" ],
      key("fr", "users.show.greeting") => [ 1, nil ]
    })

    en = model.find_by(locale: "en", translation_key: "users.show.greeting")
    expect(en.miss_count).to eq(3)
    expect(en.source).to eq("app/views/users/show.html.erb:12")
    expect(en.first_seen_at).to be_within(2.seconds).of(Time.current)
    expect(en.last_seen_at).to eq(en.first_seen_at)
    expect(model.find_by(locale: "fr").source).to be_nil
    expect(model.count).to eq(2)
  end

  it "adds to an existing row, keeps first_seen_at and the first source, moves last_seen_at" do
    row = model.create!(locale: "en", translation_key: "k", miss_count: 2, source: "a.rb:1",
                        first_seen_at: 2.days.ago, last_seen_at: 2.days.ago)

    described_class.call(counts: { key("en", "k") => [ 5, "b.rb:9" ] })

    row.reload
    expect(row.miss_count).to eq(7)
    expect(row.source).to eq("a.rb:1")
    expect(row.first_seen_at).to be_within(2.seconds).of(2.days.ago)
    expect(row.last_seen_at).to be_within(2.seconds).of(Time.current)
    expect(model.count).to eq(1)
  end

  it "fills in a source a row was created without" do
    model.create!(locale: "en", translation_key: "k", miss_count: 1, first_seen_at: 1.day.ago, last_seen_at: 1.day.ago)

    described_class.call(counts: { key("en", "k") => [ 1, "late.rb:3" ] })

    expect(model.find_by(translation_key: "k").source).to eq("late.rb:3")
  end

  it "scopes rows to the configured application" do
    app = create(:application, name: "Shop")
    RailsErrorDashboard.configuration.application_name = "Shop"

    described_class.call(counts: { key("en", "k") => [ 1, nil ] })

    expect(model.last.application_id).to eq(app.id)
  end

  it "skips malformed entries and still writes the rest" do
    described_class.call(counts: {
      "no-separator" => [ 1, nil ],
      key("", "k") => [ 1, nil ],
      key("en", "") => [ 1, nil ],
      key("en", "zero") => [ 0, nil ],
      key("en", "good") => [ 1, nil ]
    })

    expect(model.pluck(:translation_key)).to eq([ "good" ])
  end

  it "scrubs invalid bytes out of the key and source" do
    bad = "users.\xFF.name".dup.force_encoding("UTF-8")

    described_class.call(counts: { key("en", bad) => [ 1, "v\xFF.erb:1".dup.force_encoding("UTF-8") ] })

    row = model.last
    expect(row.translation_key).to be_valid_encoding
    expect(row.source).to be_valid_encoding
  end

  it "retries once as an update when another writer created the row first" do
    # With an application set the unique index has no NULL column, so the
    # second insert really collides (a NULL application_id makes the index
    # pass both rows on every database; the query merges those instead).
    app = create(:application, name: "Shop")
    RailsErrorDashboard.configuration.application_name = "Shop"

    calls = 0
    allow(model).to receive(:find_by).and_wrap_original do |m, *args, **kw|
      calls += 1
      if calls == 1
        # Simulate the race: the row appears after our read, so our insert hits the unique index.
        model.create!(locale: "en", translation_key: "k", application_id: app.id, miss_count: 10,
                      first_seen_at: Time.current, last_seen_at: Time.current)
        nil
      else
        m.call(*args, **kw)
      end
    end

    described_class.call(counts: { key("en", "k") => [ 1, nil ] })

    expect(calls).to eq(2)
    expect(model.count).to eq(1)
    expect(model.last.miss_count).to eq(11)
  end

  it "increments atomically in SQL rather than read-modify-write" do
    row = model.create!(locale: "en", translation_key: "k", miss_count: 5, first_seen_at: 1.day.ago, last_seen_at: 1.day.ago)
    expect(model).not_to receive(:find_or_initialize_by)
    expect_any_instance_of(model).not_to receive(:save!)

    described_class.call(counts: { key("en", "k") => [ 2, nil ] })

    expect(row.reload.miss_count).to eq(7)
  end

  it "does nothing without the table, and never raises" do
    allow(model).to receive(:table_exists?).and_return(false)

    expect { described_class.call(counts: { key("en", "k") => [ 1, nil ] }) }.not_to raise_error
  end

  it "does nothing for an empty or nil snapshot" do
    expect { described_class.call(counts: {}) }.not_to change(model, :count)
    expect { described_class.call(counts: nil) }.not_to change(model, :count)
  end
end
