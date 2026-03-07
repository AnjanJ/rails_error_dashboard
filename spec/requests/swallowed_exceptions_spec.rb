# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Swallowed Exceptions page", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.detect_swallowed_exceptions = false
  end

  describe "GET /error_dashboard/errors/swallowed_exceptions" do
    context "when swallowed exception detection is disabled" do
      before do
        RailsErrorDashboard.configuration.detect_swallowed_exceptions = false
        stub_const("RUBY_VERSION", "3.3.0")
      end

      it "redirects to errors index with alert" do
        get "/error_dashboard/errors/swallowed_exceptions"
        expect(response).to redirect_to("/error_dashboard/errors")
        follow_redirect!
        expect(response.body).to include("Swallowed exception detection is not enabled")
      end
    end

    context "when disabled due to Ruby < 3.3" do
      before do
        # Simulate what validate! does: auto-disable on Ruby < 3.3
        RailsErrorDashboard.configuration.detect_swallowed_exceptions = false
        stub_const("RUBY_VERSION", "3.2.0")
      end

      it "redirects with Ruby version explanation" do
        get "/error_dashboard/errors/swallowed_exceptions"
        expect(response).to redirect_to("/error_dashboard/errors")
        follow_redirect!
        expect(response.body).to include("requires Ruby 3.3+")
      end
    end

    context "when swallowed exception detection is enabled" do
      before do
        RailsErrorDashboard.configuration.detect_swallowed_exceptions = true
      end

      it "returns 200" do
        get "/error_dashboard/errors/swallowed_exceptions"
        expect(response).to have_http_status(:ok)
      end

      it "shows empty state when no swallowed exceptions exist" do
        get "/error_dashboard/errors/swallowed_exceptions"
        expect(response.body).to include("No Swallowed Exceptions Detected")
      end

      it "shows swallowed exception patterns" do
        create(:swallowed_exception,
          application: application,
          exception_class: "Stripe::CardError",
          raise_location: "app/services/payment.rb:42",
          rescue_location: "app/services/payment.rb:45",
          raise_count: 100,
          rescue_count: 99,
          period_hour: 1.hour.ago)

        get "/error_dashboard/errors/swallowed_exceptions"
        expect(response.body).to include("Stripe::CardError")
        expect(response.body).to include("app/services/payment.rb:42")
        expect(response.body).to include("app/services/payment.rb:45")
      end

      it "displays summary cards" do
        create(:swallowed_exception,
          application: application,
          raise_count: 100,
          rescue_count: 99,
          period_hour: 1.hour.ago)

        get "/error_dashboard/errors/swallowed_exceptions"
        expect(response.body).to include("Swallowed Patterns")
        expect(response.body).to include("Total Rescues")
        expect(response.body).to include("Total Raises")
      end

      it "accepts days parameter" do
        get "/error_dashboard/errors/swallowed_exceptions", params: { days: 7 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("7 Days")
      end

      it "shows rescue ratio as percentage" do
        create(:swallowed_exception,
          application: application,
          raise_count: 100,
          rescue_count: 99,
          period_hour: 1.hour.ago)

        get "/error_dashboard/errors/swallowed_exceptions"
        expect(response.body).to include("99.0%")
      end

      context "edge case params" do
        it "handles days=0 without error" do
          get "/error_dashboard/errors/swallowed_exceptions", params: { days: 0 }
          expect(response).to have_http_status(:ok)
        end

        it "handles negative days without error" do
          get "/error_dashboard/errors/swallowed_exceptions", params: { days: -5 }
          expect(response).to have_http_status(:ok)
        end

        it "handles non-numeric days param" do
          get "/error_dashboard/errors/swallowed_exceptions", params: { days: "abc" }
          expect(response).to have_http_status(:ok)
        end

        it "handles large per_page without error" do
          get "/error_dashboard/errors/swallowed_exceptions", params: { per_page: 10000 }
          expect(response).to have_http_status(:ok)
        end
      end

      context "pagination" do
        before do
          # Create enough entries to trigger pagination (>25 unique patterns)
          30.times do |i|
            create(:swallowed_exception,
              application: application,
              exception_class: "Error#{i}",
              raise_location: "app/file#{i}.rb:1",
              raise_count: 100,
              rescue_count: 99,
              period_hour: 1.hour.ago)
          end
        end

        it "paginates results" do
          get "/error_dashboard/errors/swallowed_exceptions"
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Swallowed Exception Patterns")
        end

        it "renders page 2" do
          get "/error_dashboard/errors/swallowed_exceptions", params: { page: 2 }
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end
end
