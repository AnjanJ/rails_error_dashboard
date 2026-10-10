# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::MissingTranslationTracker do
  let(:model) { RailsErrorDashboard::MissingTranslation }

  before do
    RailsErrorDashboard.configuration.enable_missing_translation_tracking = true
    described_class.reset!
  end

  after do
    described_class.reset!
    RailsErrorDashboard.reset_configuration!
  end

  describe ".record" do
    it "buffers a miss without touching the database" do
      expect {
        described_class.record(locale: "en", key: "users.show.greeting")
      }.not_to change(model, :count)

      counts = described_class.buffered_counts
      expect(counts.size).to eq(1)
      expect(counts.values.first[0]).to eq(1)
    end

    it "increments the count for the same locale and key" do
      3.times { described_class.record(locale: "en", key: "users.show.greeting") }

      expect(described_class.buffered_counts.values.first[0]).to eq(3)
      expect(described_class.buffered_counts.size).to eq(1)
    end

    it "keeps the same key in different locales apart" do
      described_class.record(locale: "en", key: "users.show.greeting")
      described_class.record(locale: "fr", key: "users.show.greeting")

      expect(described_class.buffered_counts.size).to eq(2)
    end

    it "records the host call site for a new key, relative to Rails.root when inside it" do
      described_class.record(locale: "en", key: "users.show.greeting")

      source = described_class.buffered_counts.values.first[1]
      expect(source).to match(/missing_translation_tracker_spec\.rb:\d+\z/)
      expect(source).not_to include("/gems/")
    end

    it "keeps an explicit source as given" do
      described_class.record(locale: "en", key: "k", source: "app/views/users/show.html.erb:12")

      expect(described_class.buffered_counts.values.first[1]).to eq("app/views/users/show.html.erb:12")
    end

    it "truncates locale, key and source to their column limits" do
      described_class.record(locale: "x" * 100, key: "k" * 300, source: "s" * 400)

      locale, key = described_class.parse_key(described_class.buffered_counts.keys.first)
      expect(locale.length).to eq(described_class::MAX_LOCALE_LENGTH)
      expect(key.length).to eq(described_class::MAX_KEY_LENGTH)
      expect(described_class.buffered_counts.values.first[1].length).to eq(described_class::MAX_SOURCE_LENGTH)
    end

    it "strips the separator from a key so it cannot shift columns" do
      described_class.record(locale: "en", key: "bad\x1Fkey")

      expect(described_class.parse_key(described_class.buffered_counts.keys.first)).to eq([ "en", "badkey" ])
    end

    it "no-ops when tracking is disabled" do
      RailsErrorDashboard.configuration.enable_missing_translation_tracking = false

      described_class.record(locale: "en", key: "k")

      expect(described_class.buffered_counts).to be_empty
    end

    it "never raises, even when the configuration is unreadable" do
      allow(RailsErrorDashboard).to receive(:configuration).and_raise(RuntimeError, "boom")

      expect { described_class.record(locale: "en", key: "k") }.not_to raise_error
    end

    context "when the buffer is full" do
      before do
        stub_const("#{described_class}::MAX_BUFFERED_KEYS", 3)
        3.times { |i| described_class.record(locale: "en", key: "key.#{i}") }
      end

      it "counts further new keys in the overflow bucket instead of growing" do
        described_class.record(locale: "en", key: "key.new")
        described_class.record(locale: "en", key: "key.other")

        counts = described_class.buffered_counts
        expect(counts.size).to eq(4)
        expect(counts[described_class.overflow_key][0]).to eq(2)
      end

      it "still counts keys it already holds" do
        described_class.record(locale: "en", key: "key.0")

        expect(described_class.buffered_counts.values.map(&:first).sum).to eq(4)
        expect(described_class.buffered_counts).not_to have_key(described_class.overflow_key)
      end
    end
  end

  describe ".flush!" do
    it "writes the buffer out and clears it" do
      2.times { described_class.record(locale: "en", key: "users.show.greeting", source: "app/views/users/show.html.erb:3") }

      expect { described_class.flush! }.to change(model, :count).by(1)

      row = model.last
      expect(row.locale).to eq("en")
      expect(row.translation_key).to eq("users.show.greeting")
      expect(row.miss_count).to eq(2)
      expect(row.source).to eq("app/views/users/show.html.erb:3")
      expect(described_class.buffered_counts).to be_empty
    end

    it "is a no-op on an empty buffer" do
      expect { described_class.flush! }.not_to change(model, :count)
    end

    it "stores the overflow bucket under its reserved locale and key" do
      stub_const("#{described_class}::MAX_BUFFERED_KEYS", 1)
      described_class.record(locale: "en", key: "a")
      described_class.record(locale: "en", key: "b")

      described_class.flush!

      overflow = model.find_by(translation_key: model::OVERFLOW_KEY)
      expect(overflow.locale).to eq(model::OVERFLOW_LOCALE)
      expect(overflow.miss_count).to eq(1)
    end

    it "clears the buffer before writing, so a failed write cannot double-count later" do
      described_class.record(locale: "en", key: "k")
      allow(RailsErrorDashboard::Commands::FlushMissingTranslations).to receive(:call).and_raise(RuntimeError, "db gone")

      expect { described_class.flush! }.not_to raise_error
      expect(described_class.buffered_counts).to be_empty
    end
  end

  describe ".flush_if_due!" do
    it "does nothing before the interval has elapsed" do
      described_class.record(locale: "en", key: "k")

      expect { described_class.flush_if_due! }.not_to change(model, :count)
    end

    it "flushes once the buffer has waited the interval" do
      described_class.record(locale: "en", key: "k")
      Thread.current[described_class::DEADLINE_THREAD_KEY] -= described_class::FLUSH_INTERVAL

      expect { described_class.flush_if_due! }.to change(model, :count).by(1)
    end

    it "does nothing when tracking is disabled" do
      described_class.record(locale: "en", key: "k")
      Thread.current[described_class::DEADLINE_THREAD_KEY] -= described_class::FLUSH_INTERVAL
      RailsErrorDashboard.configuration.enable_missing_translation_tracking = false

      expect { described_class.flush_if_due! }.not_to change(model, :count)
    end
  end

  describe ".flush_all_threads!" do
    it "drains a buffer held by another thread" do
      other = Thread.new do
        described_class.record(locale: "de", key: "k")
        sleep
      end
      sleep 0.01 until other.status == "sleep"

      expect { described_class.flush_all_threads! }.to change(model, :count).by(1)
      expect(other[described_class::COUNTS_THREAD_KEY]).to be_empty
    ensure
      other&.kill
    end
  end

  describe ".parse_key" do
    it "always yields two fields" do
      expect(described_class.parse_key("en")).to eq([ "en", "" ])
      expect(described_class.parse_key("en\x1Fa.b")).to eq([ "en", "a.b" ])
    end
  end
end
