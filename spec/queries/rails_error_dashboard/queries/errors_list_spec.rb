# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::ErrorsList do
  describe ".call" do
    let!(:error1) { create(:error_log, error_type: "NoMethodError", platform: "iOS", occurred_at: 1.hour.ago) }
    let!(:error2) { create(:error_log, error_type: "ArgumentError", platform: "Android", occurred_at: 2.hours.ago) }
    let!(:error3) { create(:error_log, error_type: "NoMethodError", platform: "API", occurred_at: 3.hours.ago) }
    let!(:resolved_error) { create(:error_log, :resolved, occurred_at: 4.hours.ago) }

    context "with no filters" do
      it "returns only unresolved errors by default" do
        result = described_class.call

        expect(result.count).to eq(3)
        expect(result).not_to include(resolved_error)
      end

      it "orders by occurred_at descending" do
        result = described_class.call

        expect(result.first).to eq(error1)
        expect(result.last).to eq(error3)
      end

      it "returns ActiveRecord relation" do
        result = described_class.call

        expect(result).to be_a(ActiveRecord::Relation)
      end
    end

    describe "filtering by error_type" do
      it "filters by NoMethodError" do
        result = described_class.call(error_type: "NoMethodError")

        expect(result.count).to eq(2)
        expect(result).to include(error1, error3)
      end

      it "filters by ArgumentError" do
        result = described_class.call(error_type: "ArgumentError")

        expect(result.count).to eq(1)
        expect(result).to include(error2)
      end

      it "returns empty when no matches" do
        result = described_class.call(error_type: "TypeError")

        expect(result.count).to eq(0)
      end
    end

    describe "filtering by resolved status" do
      it "filters unresolved errors with string 'true'" do
        result = described_class.call(unresolved: "true")

        expect(result.count).to eq(3)
        expect(result).not_to include(resolved_error)
      end

      it "filters unresolved errors with boolean true" do
        result = described_class.call(unresolved: true)

        expect(result.count).to eq(3)
        expect(result).not_to include(resolved_error)
      end

      it "shows all errors when unresolved is false" do
        result = described_class.call(unresolved: false)

        expect(result.count).to eq(4)
      end

      it "shows only unresolved errors when unresolved is not provided (default)" do
        result = described_class.call

        expect(result.count).to eq(3)
        expect(result).not_to include(resolved_error)
      end
    end

    describe "filtering by platform" do
      it "filters by iOS platform" do
        result = described_class.call(platform: "iOS")

        expect(result.count).to eq(1)
        expect(result).to include(error1)
      end

      it "filters by Android platform" do
        result = described_class.call(platform: "Android")

        expect(result.count).to eq(1)
        expect(result).to include(error2)
      end

      it "filters by API platform" do
        result = described_class.call(platform: "API")

        expect(result.count).to eq(1)
        expect(result).to include(error3)
      end
    end

    describe "filtering by search" do
      let!(:searchable_error) { create(:error_log, message: "User not found in database", occurred_at: 30.minutes.ago) }

      it "searches in error message" do
        result = described_class.call(search: "not found")

        expect(result).to include(searchable_error)
      end

      it "is case insensitive" do
        result = described_class.call(search: "USER NOT FOUND")

        expect(result).to include(searchable_error)
      end

      it "performs partial matching" do
        result = described_class.call(search: "database")

        expect(result).to include(searchable_error)
      end

      it "returns empty when no matches" do
        result = described_class.call(search: "xyz123nonexistent")

        expect(result.count).to eq(0)
      end
    end

    describe "combining multiple filters" do
      it "combines error_type and platform" do
        result = described_class.call(
          error_type: "NoMethodError",
          platform: "iOS"
        )

        expect(result.count).to eq(1)
        expect(result).to include(error1)
      end

      it "combines platform and unresolved" do
        result = described_class.call(
          platform: "iOS",
          unresolved: true
        )

        expect(result.count).to eq(1)
        expect(result).to include(error1)
      end

      it "combines all filters" do
        result = described_class.call(
          error_type: "NoMethodError",
          platform: "iOS",
          unresolved: true
        )

        expect(result.count).to eq(1)
        expect(result).to include(error1)
      end

      it "returns empty when filters don't match" do
        result = described_class.call(
          error_type: "ArgumentError",
          platform: "iOS"
        )

        expect(result.count).to eq(0)
      end
    end

    describe "with empty filters hash" do
      it "returns only unresolved errors by default" do
        result = described_class.call({})

        expect(result.count).to eq(3)
        expect(result).not_to include(resolved_error)
      end
    end

    describe "chainable result" do
      it "can be chained with additional scopes" do
        result = described_class.call(error_type: "NoMethodError")
                                .limit(1)

        expect(result.count).to eq(1)
      end

      it "can be paginated" do
        result = described_class.call.offset(1).limit(2)

        expect(result.count).to eq(2)
      end
    end
  end
end
