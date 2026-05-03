# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Local Variables display on error show page", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    RailsErrorDashboard.configuration.enable_local_variables = true
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_local_variables = false
  end

  describe "GET /error_dashboard/errors/:id" do
    context "when local_variables column exists and has data" do
      let!(:error_log) do
        create(:error_log, application: application).tap do |e|
          next unless e.class.column_names.include?("local_variables")
          e.update_column(:local_variables, {
            "user_name" => { "type" => "String", "value" => "Gandalf", "truncated" => false },
            "count" => { "type" => "Integer", "value" => 42, "truncated" => false },
            "api_key" => { "type" => "String", "value" => "[FILTERED]", "truncated" => false, "filtered" => true }
          }.to_json)
        end
      end

      before do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")
      end

      it "renders the local variables section" do
        get "/error_dashboard/errors/#{error_log.id}"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Local Variables")
        expect(response.body).to include("3 captured")
      end

      it "displays variable names and values" do
        get "/error_dashboard/errors/#{error_log.id}"
        expect(response.body).to include("user_name")
        expect(response.body).to include("Gandalf")
        expect(response.body).to include("count")
      end

      it "shows filtered badge for sensitive variables" do
        get "/error_dashboard/errors/#{error_log.id}"
        expect(response.body).to include("[FILTERED]")
        expect(response.body).to include("bg-warning")
      end

      it "shows truncated badge when variable is truncated" do
        error_log.update_column(:local_variables, {
          "long_data" => { "type" => "String", "value" => "x" * 200, "truncated" => true }
        }.to_json)

        get "/error_dashboard/errors/#{error_log.id}"
        expect(response.body).to include("truncated")
        expect(response.body).to include("bg-info")
      end
    end

    context "when local_variables is nil or empty" do
      let!(:error_log) { create(:error_log, application: application) }

      it "does not render the local variables section" do
        get "/error_dashboard/errors/#{error_log.id}"
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("section-local-variables")
      end
    end

    context "when local_variables contains malformed JSON" do
      let!(:error_log) { create(:error_log, application: application) }

      before do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")
        error_log.update_column(:local_variables, "not valid json {{{")
      end

      it "does not crash and hides the section" do
        get "/error_dashboard/errors/#{error_log.id}"
        expect(response).to have_http_status(:ok)
        # Malformed JSON => rescue {} => empty => section hidden
        expect(response.body).not_to include("section-local-variables")
      end
    end

    context "when enable_local_variables is false" do
      before do
        RailsErrorDashboard.configuration.enable_local_variables = false
      end

      let!(:error_log) do
        create(:error_log, application: application).tap do |e|
          next unless e.class.column_names.include?("local_variables")
          e.update_column(:local_variables, { "x" => { "type" => "Integer", "value" => 1 } }.to_json)
        end
      end

      it "does not render the section even if data exists" do
        get "/error_dashboard/errors/#{error_log.id}"
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("section-local-variables")
      end
    end

    context "XSS safety" do
      let!(:error_log) do
        create(:error_log, application: application).tap do |e|
          next unless e.class.column_names.include?("local_variables")
          e.update_column(:local_variables, {
            '<script>alert("xss")</script>' => {
              "type" => '<img onerror="alert(1)">',
              "value" => '<script>steal_cookies()</script>',
              "truncated" => false
            }
          }.to_json)
        end
      end

      before do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")
      end

      it "escapes HTML in variable names, types, and values" do
        get "/error_dashboard/errors/#{error_log.id}"
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('<script>alert("xss")</script>')
        expect(response.body).not_to include('<img onerror="alert(1)">')
        expect(response.body).not_to include("<script>steal_cookies()</script>")
        # Escaped versions should be present
        expect(response.body).to include("&lt;script&gt;")
      end
    end

    context "when local_variables column has a non-Hash JSON shape" do
      # Regression: the partial parsed and immediately called .any? / .each on
      # the result. If a serializer ever wrote an Array or scalar instead of
      # a Hash, the show page would crash with NoMethodError.
      let!(:error_log) do
        create(:error_log, application: application).tap do |e|
          next unless e.class.column_names.include?("local_variables")
          e.update_column(:local_variables, "[1, 2, 3]") # Array, not Hash
        end
      end

      before do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")
      end

      it "renders the page without raising and hides the section" do
        get "/error_dashboard/errors/#{error_log.id}"
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('id="section-local-variables"')
      end
    end
  end
end
