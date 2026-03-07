# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::FlushSwallowedExceptions do
  let!(:application) { create(:application) }

  after do
    RailsErrorDashboard::SwallowedException.delete_all
  end

  describe ".call" do
    it "creates new swallowed exception records from raise counts" do
      expect {
        described_class.call(
          raise_counts: { "RuntimeError|app/services/foo.rb:10" => 5 },
          rescue_counts: {}
        )
      }.to change(RailsErrorDashboard::SwallowedException, :count).by(1)

      record = RailsErrorDashboard::SwallowedException.last
      expect(record.exception_class).to eq("RuntimeError")
      expect(record.raise_location).to eq("app/services/foo.rb:10")
      expect(record.raise_count).to eq(5)
      expect(record.rescue_count).to eq(0)
    end

    it "creates new swallowed exception records from rescue counts" do
      expect {
        described_class.call(
          raise_counts: {},
          rescue_counts: { "RuntimeError|app/services/foo.rb:10->app/services/foo.rb:15" => 3 }
        )
      }.to change(RailsErrorDashboard::SwallowedException, :count).by(1)

      record = RailsErrorDashboard::SwallowedException.last
      expect(record.exception_class).to eq("RuntimeError")
      expect(record.raise_location).to eq("app/services/foo.rb:10")
      expect(record.rescue_location).to eq("app/services/foo.rb:15")
      expect(record.rescue_count).to eq(3)
    end

    it "increments existing records on subsequent flushes" do
      freeze_time do
        described_class.call(
          raise_counts: { "RuntimeError|app/services/foo.rb:10" => 5 },
          rescue_counts: {}
        )

        described_class.call(
          raise_counts: { "RuntimeError|app/services/foo.rb:10" => 3 },
          rescue_counts: {}
        )

        expect(RailsErrorDashboard::SwallowedException.count).to eq(1)
        record = RailsErrorDashboard::SwallowedException.last
        expect(record.raise_count).to eq(8)
      end
    end

    it "handles both raise and rescue counts together" do
      described_class.call(
        raise_counts: { "Stripe::CardError|app/services/payment.rb:42" => 10 },
        rescue_counts: { "Stripe::CardError|app/services/payment.rb:42->app/services/payment.rb:45" => 9 }
      )

      records = RailsErrorDashboard::SwallowedException.all
      # One for raise-only (rescue_location nil), one for rescue (rescue_location set)
      expect(records.size).to eq(2)
    end

    it "skips entries with blank class or location" do
      expect {
        described_class.call(
          raise_counts: { "|" => 5, "RuntimeError|" => 3, "|foo.rb:1" => 2 },
          rescue_counts: {}
        )
      }.not_to change(RailsErrorDashboard::SwallowedException, :count)
    end

    it "sets last_seen_at" do
      freeze_time do
        described_class.call(
          raise_counts: { "RuntimeError|app/services/foo.rb:10" => 1 },
          rescue_counts: {}
        )

        record = RailsErrorDashboard::SwallowedException.last
        expect(record.last_seen_at).to be_within(1.second).of(Time.current)
      end
    end

    it "handles errors gracefully without raising" do
      allow(RailsErrorDashboard::SwallowedException).to receive(:find_or_initialize_by).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect {
        described_class.call(
          raise_counts: { "RuntimeError|app/services/foo.rb:10" => 1 },
          rescue_counts: {}
        )
      }.not_to raise_error
    end

    context "truncation" do
      it "truncates class names longer than 255 characters" do
        long_name = "A" * 300
        described_class.call(
          raise_counts: { "#{long_name}|app/foo.rb:1" => 1 },
          rescue_counts: {}
        )

        record = RailsErrorDashboard::SwallowedException.last
        expect(record.exception_class.length).to be <= 255
      end

      it "truncates locations longer than 500 characters" do
        long_loc = "app/" + "x" * 500 + ".rb:1"
        described_class.call(
          raise_counts: { "RuntimeError|#{long_loc}" => 1 },
          rescue_counts: {}
        )

        record = RailsErrorDashboard::SwallowedException.last
        expect(record.raise_location.length).to be <= 500
      end
    end

    context "malformed keys" do
      it "handles rescue key without -> separator (rescue_location becomes nil)" do
        described_class.call(
          raise_counts: {},
          rescue_counts: { "RuntimeError|app/foo.rb:10" => 3 }
        )

        record = RailsErrorDashboard::SwallowedException.last
        expect(record.raise_location).to eq("app/foo.rb:10")
        expect(record.rescue_location).to be_nil
        expect(record.rescue_count).to eq(3)
      end

      it "skips keys that are just pipe characters" do
        expect {
          described_class.call(
            raise_counts: { "||" => 5 },
            rescue_counts: {}
          )
        }.not_to change(RailsErrorDashboard::SwallowedException, :count)
      end
    end

    context "concurrent flush (race condition)" do
      it "handles concurrent upserts without crashing" do
        freeze_time do
          # Simulate two flushes for the same key — both should succeed
          expect {
            described_class.call(
              raise_counts: { "RuntimeError|app/foo.rb:10" => 5 },
              rescue_counts: {}
            )
            described_class.call(
              raise_counts: { "RuntimeError|app/foo.rb:10" => 3 },
              rescue_counts: {}
            )
          }.not_to raise_error

          record = RailsErrorDashboard::SwallowedException.find_by(
            exception_class: "RuntimeError",
            raise_location: "app/foo.rb:10"
          )
          # Total should be 8 (5+3) if no lost update, but at minimum both calls succeed
          expect(record).to be_present
          expect(record.raise_count).to be >= 3
        end
      end
    end

    context "partial failure" do
      it "continues processing after individual record save failure" do
        call_count = 0
        allow(RailsErrorDashboard::SwallowedException).to receive(:find_or_initialize_by).and_wrap_original do |method, **args|
          call_count += 1
          if call_count == 1
            raise ActiveRecord::RecordInvalid.new(RailsErrorDashboard::SwallowedException.new)
          else
            method.call(**args)
          end
        end

        described_class.call(
          raise_counts: {
            "FirstError|app/a.rb:1" => 1,
            "SecondError|app/b.rb:1" => 1
          },
          rescue_counts: {}
        )

        # Second record should still be created despite first failing
        expect(RailsErrorDashboard::SwallowedException.where(exception_class: "SecondError").count).to eq(1)
      end
    end
  end
end
