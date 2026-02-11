# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::FilterOptions do
  describe ".call" do
    let!(:error1) { create(:error_log, error_type: "NoMethodError", platform: "iOS") }
    let!(:error2) { create(:error_log, error_type: "ArgumentError", platform: "Android") }
    let!(:error3) { create(:error_log, error_type: "TypeError", platform: "API") }
    let!(:error4) { create(:error_log, error_type: "NoMethodError", platform: "iOS") }

    it "returns hash with filter options" do
      result = described_class.call

      expect(result).to be_a(Hash)
      expect(result.keys).to include(:error_types, :platforms)
    end

    describe "error_types" do
      it "returns distinct error types" do
        result = described_class.call

        expect(result[:error_types]).to be_an(Array)
        expect(result[:error_types]).to include("NoMethodError", "ArgumentError", "TypeError")
      end

      it "sorts error types alphabetically" do
        result = described_class.call

        expect(result[:error_types]).to eq(result[:error_types].sort)
      end

      it "does not include duplicates" do
        create(:error_log, error_type: "NoMethodError")

        result = described_class.call

        expect(result[:error_types].count("NoMethodError")).to eq(1)
      end
    end

    describe "platforms" do
      it "returns distinct platforms" do
        result = described_class.call

        expect(result[:platforms]).to be_an(Array)
        expect(result[:platforms]).to include("iOS", "Android", "API")
      end

      it "does not include duplicates" do
        create(:error_log, platform: "iOS")

        result = described_class.call

        expect(result[:platforms].count("iOS")).to eq(1)
      end

      it "excludes nil values" do
        create(:error_log, platform: nil)

        result = described_class.call

        expect(result[:platforms]).not_to include(nil)
      end
    end

    describe "assignees" do
      before do
        RailsErrorDashboard::ErrorLog.destroy_all
      end

      it "returns distinct assigned_to values" do
        create(:error_log, assigned_to: "gandalf")
        create(:error_log, assigned_to: "aragorn")
        create(:error_log, assigned_to: "gandalf")

        result = described_class.call

        expect(result[:assignees]).to contain_exactly("aragorn", "gandalf")
      end

      it "sorts assignees alphabetically" do
        create(:error_log, assigned_to: "gandalf")
        create(:error_log, assigned_to: "aragorn")

        result = described_class.call

        expect(result[:assignees]).to eq([ "aragorn", "gandalf" ])
      end

      it "excludes errors with nil assigned_to" do
        create(:error_log, assigned_to: nil)
        create(:error_log, assigned_to: "gandalf")

        result = described_class.call

        expect(result[:assignees]).to eq([ "gandalf" ])
      end

      it "returns empty array when no assignments exist" do
        create(:error_log, assigned_to: nil)

        result = described_class.call

        expect(result[:assignees]).to eq([])
      end

      context "with application_id filter" do
        let!(:app1) { create(:application) }
        let!(:app2) { create(:application) }

        before do
          create(:error_log, application: app1, assigned_to: "gandalf")
          create(:error_log, application: app2, assigned_to: "sauron")
        end

        it "filters assignees by application" do
          result = described_class.call(application_id: app1.id)

          expect(result[:assignees]).to eq([ "gandalf" ])
          expect(result[:assignees]).not_to include("sauron")
        end
      end
    end

    context "with no errors" do
      before do
        RailsErrorDashboard::ErrorLog.destroy_all
      end

      it "returns empty arrays" do
        result = described_class.call

        expect(result[:error_types]).to eq([])
        expect(result[:platforms]).to eq([])
      end
    end

    context "with single error" do
      before do
        RailsErrorDashboard::ErrorLog.destroy_all
        create(:error_log, error_type: "StandardError", platform: "Web")
      end

      it "returns single values" do
        result = described_class.call

        expect(result[:error_types]).to eq([ "StandardError" ])
        expect(result[:platforms]).to eq([ "Web" ])
      end
    end
  end
end
