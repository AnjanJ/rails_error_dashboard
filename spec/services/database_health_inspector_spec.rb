# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::DatabaseHealthInspector do
  describe ".call" do
    subject(:result) { described_class.call }

    it "returns a Hash" do
      expect(result).to be_a(Hash)
    end

    it "includes all expected keys" do
      expect(result).to have_key(:adapter)
      expect(result).to have_key(:postgresql)
      expect(result).to have_key(:connection_pool)
      expect(result).to have_key(:tables)
      expect(result).to have_key(:indexes)
      expect(result).to have_key(:unused_indexes)
      expect(result).to have_key(:activity)
    end

    describe ":connection_pool" do
      it "includes pool stats" do
        pool = result[:connection_pool]
        expect(pool).to be_a(Hash)
        expect(pool).to have_key(:size)
        expect(pool).to have_key(:busy)
        expect(pool).to have_key(:dead)
        expect(pool).to have_key(:idle)
        expect(pool).to have_key(:waiting)
      end
    end

    describe ":adapter" do
      it "returns the adapter name" do
        expect(result[:adapter]).to be_a(String)
      end
    end

    context "when running on SQLite" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("SQLite")
      end

      it "sets postgresql to false" do
        expect(result[:postgresql]).to eq(false)
      end

      it "returns nil for tables" do
        expect(result[:tables]).to be_nil
      end

      it "returns nil for indexes" do
        expect(result[:indexes]).to be_nil
      end

      it "returns nil for activity" do
        expect(result[:activity]).to be_nil
      end

      it "still returns connection_pool stats" do
        expect(result[:connection_pool]).to be_a(Hash)
      end
    end

    context "when connection_pool raises" do
      before do
        allow(ActiveRecord::Base).to receive(:connection_pool).and_raise(RuntimeError, "Pool error")
      end

      it "does not raise" do
        expect { result }.not_to raise_error
      end

      it "returns nil for connection_pool" do
        expect(result[:connection_pool]).to be_nil
      end
    end

    context "when PostgreSQL is detected" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("PostgreSQL")
      end

      it "sets postgresql to true" do
        expect(result[:postgresql]).to eq(true)
      end

      it "attempts to query pg_stat_user_tables" do
        allow(ActiveRecord::Base.connection).to receive(:select_all).and_return([])
        result
        expect(ActiveRecord::Base.connection).to have_received(:select_all).at_least(:once)
      end

      context "when pg_stat queries fail" do
        before do
          allow(ActiveRecord::Base.connection).to receive(:select_all).and_raise(ActiveRecord::StatementInvalid, "relation does not exist")
        end

        it "does not raise" do
          expect { result }.not_to raise_error
        end

        it "returns nil for tables" do
          expect(result[:tables]).to be_nil
        end

        it "returns nil for indexes" do
          expect(result[:indexes]).to be_nil
        end

        it "returns nil for activity" do
          expect(result[:activity]).to be_nil
        end

        it "still returns connection_pool stats" do
          expect(result[:connection_pool]).to be_a(Hash)
        end
      end
    end

    context "when entire call fails" do
      before do
        allow_any_instance_of(described_class).to receive(:call).and_raise(RuntimeError, "Unexpected")
      end

      it "returns a safe fallback hash" do
        result = described_class.call
        expect(result).to be_a(Hash)
        expect(result[:postgresql]).to eq(false)
        expect(result[:connection_pool]).to be_nil
      end
    end
  end
end
