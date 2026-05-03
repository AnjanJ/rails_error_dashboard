# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Diagnostic Dumps page", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_diagnostic_dump = false
    ActionController::Base.allow_forgery_protection = true
  end

  describe "GET /error_dashboard/errors/diagnostic_dumps" do
    context "when diagnostic dump is disabled" do
      before { RailsErrorDashboard.configuration.enable_diagnostic_dump = false }

      it "redirects to errors index with alert" do
        get "/error_dashboard/errors/diagnostic_dumps"
        expect(response).to redirect_to("/error_dashboard/errors")
        follow_redirect!
        expect(response.body).to include("Diagnostic dumps are not enabled")
      end
    end

    context "when diagnostic dump is enabled" do
      before { RailsErrorDashboard.configuration.enable_diagnostic_dump = true }

      it "returns 200" do
        get "/error_dashboard/errors/diagnostic_dumps"
        expect(response).to have_http_status(:ok)
      end

      it "shows empty state when no dumps exist" do
        get "/error_dashboard/errors/diagnostic_dumps"
        expect(response.body).to include("No Diagnostic Dumps Yet")
        expect(response.body).to include("How diagnostic dumps work")
      end

      it "shows dump data when dumps exist" do
        dump_data = {
          captured_at: Time.current.iso8601,
          pid: 1234,
          uptime_seconds: 3600,
          environment: { ruby_version: "3.2.0", rails_version: "7.1.0", server: "puma" },
          system_health: { thread_count: 5, process_memory_mb: 256.5, gc: { heap_live_slots: 100000, major_gc_count: 3 }, connection_pool: { busy: 2, size: 5 } },
          threads: [ { name: "main", status: "run", alive: true } ],
          gc: { heap_live_slots: 100000 },
          object_counts: { TOTAL: 50000 }
        }

        RailsErrorDashboard::DiagnosticDump.create!(
          application: application,
          dump_data: dump_data.to_json,
          captured_at: 1.hour.ago,
          note: "deploy check"
        )

        get "/error_dashboard/errors/diagnostic_dumps"
        expect(response.body).to include("Dump History")
        expect(response.body).to include("PID: 1234")
        expect(response.body).to include("deploy check")
        expect(response.body).to include("Ruby 3.2.0")
        expect(response.body).to include("Rails 7.1.0")
      end

      it "displays summary cards" do
        dump_data = {
          captured_at: Time.current.iso8601,
          pid: 1234,
          system_health: { thread_count: 8, process_memory_mb: 512.0 }
        }

        RailsErrorDashboard::DiagnosticDump.create!(
          application: application,
          dump_data: dump_data.to_json,
          captured_at: 1.hour.ago
        )

        get "/error_dashboard/errors/diagnostic_dumps"
        expect(response.body).to include("Total Dumps")
        expect(response.body).to include("Threads (Latest)")
        expect(response.body).to include("Memory (Latest)")
      end

      it "formats heap_live_slots with thousand separators" do
        # Regression: was `to_s(:delimited)` which Rails 7 removed; the silent
        # `rescue` masked a TypeError and rendered the raw integer.
        dump_data = {
          captured_at: Time.current.iso8601,
          system_health: { gc: { heap_live_slots: 1_234_567, major_gc_count: 8 } }
        }

        RailsErrorDashboard::DiagnosticDump.create!(
          application: application,
          dump_data: dump_data.to_json,
          captured_at: 1.hour.ago
        )

        get "/error_dashboard/errors/diagnostic_dumps"
        expect(response.body).to include("1,234,567")
        expect(response.body).not_to match(/Live:\s*1234567\b/)
      end

      it "shows expandable JSON detail block" do
        dump_data = { captured_at: Time.current.iso8601, pid: 9999 }

        RailsErrorDashboard::DiagnosticDump.create!(
          application: application,
          dump_data: dump_data.to_json,
          captured_at: 1.hour.ago
        )

        get "/error_dashboard/errors/diagnostic_dumps"
        expect(response.body).to include("Details")
        expect(response.body).to include("<pre")
        expect(response.body).to include("9999")
      end

      it "does not display note badge when note is nil" do
        RailsErrorDashboard::DiagnosticDump.create!(
          application: application,
          dump_data: { captured_at: Time.current.iso8601 }.to_json,
          captured_at: 1.hour.ago,
          note: nil
        )

        get "/error_dashboard/errors/diagnostic_dumps"
        expect(response.body).not_to include("badge bg-secondary")
      end

      it "renders without error when dump_data contains malformed JSON" do
        RailsErrorDashboard::DiagnosticDump.create!(
          application: application,
          dump_data: "this is not json {{{",
          captured_at: 1.hour.ago
        )

        get "/error_dashboard/errors/diagnostic_dumps"
        expect(response).to have_http_status(:ok)
        # Malformed JSON is parsed as {} via rescue — page still renders safely
        expect(response.body).to include("Dump History")
      end

      context "application filter" do
        let!(:other_app) { create(:application, name: "OtherApp") }

        before do
          RailsErrorDashboard::DiagnosticDump.create!(
            application: application,
            dump_data: { captured_at: Time.current.iso8601, pid: 1111 }.to_json,
            captured_at: 1.hour.ago
          )
          RailsErrorDashboard::DiagnosticDump.create!(
            application: other_app,
            dump_data: { captured_at: Time.current.iso8601, pid: 2222 }.to_json,
            captured_at: 2.hours.ago
          )
        end

        it "shows all dumps when no application filter" do
          get "/error_dashboard/errors/diagnostic_dumps"
          expect(response.body).to include("PID: 1111")
          expect(response.body).to include("PID: 2222")
        end

        it "filters by application_id when provided" do
          get "/error_dashboard/errors/diagnostic_dumps", params: { application_id: application.id }
          expect(response.body).to include("PID: 1111")
          expect(response.body).not_to include("PID: 2222")
        end
      end

      context "pagination" do
        before do
          30.times do |i|
            RailsErrorDashboard::DiagnosticDump.create!(
              application: application,
              dump_data: { captured_at: Time.current.iso8601, pid: 5000 + i }.to_json,
              captured_at: i.hours.ago
            )
          end
        end

        it "paginates results" do
          get "/error_dashboard/errors/diagnostic_dumps"
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Dump History")
        end

        it "renders page 2" do
          get "/error_dashboard/errors/diagnostic_dumps", params: { page: 2 }
          expect(response).to have_http_status(:ok)
        end
      end

      context "XSS safety" do
        it "escapes HTML in note field" do
          RailsErrorDashboard::DiagnosticDump.create!(
            application: application,
            dump_data: { captured_at: Time.current.iso8601 }.to_json,
            captured_at: 1.hour.ago,
            note: '<script>alert("xss")</script>'
          )

          get "/error_dashboard/errors/diagnostic_dumps"
          expect(response.body).not_to include('<script>alert("xss")</script>')
          expect(response.body).to include("&lt;script&gt;")
        end

        it "escapes HTML in dump_data JSON values" do
          malicious_data = {
            captured_at: Time.current.iso8601,
            environment: { ruby_version: '<img src=x onerror=alert(1)>' }
          }

          RailsErrorDashboard::DiagnosticDump.create!(
            application: application,
            dump_data: malicious_data.to_json,
            captured_at: 1.hour.ago
          )

          get "/error_dashboard/errors/diagnostic_dumps"
          expect(response.body).not_to include('<img src=x onerror=alert(1)>')
          expect(response.body).to include("&lt;img src=x onerror=alert(1)&gt;")
        end
      end
    end
  end

  describe "POST /error_dashboard/errors/create_diagnostic_dump" do
    context "when diagnostic dump is disabled" do
      before { RailsErrorDashboard.configuration.enable_diagnostic_dump = false }

      it "redirects to errors index with alert" do
        post "/error_dashboard/errors/create_diagnostic_dump"
        expect(response).to redirect_to("/error_dashboard/errors")
        follow_redirect!
        expect(response.body).to include("Diagnostic dumps are not enabled")
      end
    end

    context "when diagnostic dump is enabled" do
      before { RailsErrorDashboard.configuration.enable_diagnostic_dump = true }

      it "creates a diagnostic dump and redirects" do
        expect {
          post "/error_dashboard/errors/create_diagnostic_dump"
        }.to change(RailsErrorDashboard::DiagnosticDump, :count).by(1)

        expect(response).to redirect_to("/error_dashboard/errors/diagnostic_dumps")
      end

      it "shows success flash message" do
        post "/error_dashboard/errors/create_diagnostic_dump"
        follow_redirect!
        expect(response.body).to include("Diagnostic dump captured successfully")
      end

      it "saves note from params" do
        post "/error_dashboard/errors/create_diagnostic_dump", params: { note: "pre-deploy snapshot" }
        dump = RailsErrorDashboard::DiagnosticDump.last
        expect(dump.note).to eq("pre-deploy snapshot")
      end

      it "saves nil note when not provided" do
        post "/error_dashboard/errors/create_diagnostic_dump"
        dump = RailsErrorDashboard::DiagnosticDump.last
        expect(dump.note).to be_nil
      end

      it "stores valid JSON in dump_data" do
        post "/error_dashboard/errors/create_diagnostic_dump"
        dump = RailsErrorDashboard::DiagnosticDump.last
        parsed = JSON.parse(dump.dump_data)
        expect(parsed).to have_key("captured_at")
        expect(parsed).to have_key("pid")
        expect(parsed).to have_key("environment")
        expect(parsed).to have_key("system_health")
      end

      it "handles DB write failure gracefully" do
        allow(RailsErrorDashboard::DiagnosticDump).to receive(:create!).and_raise(
          ActiveRecord::StatementInvalid, "disk full"
        )

        post "/error_dashboard/errors/create_diagnostic_dump"
        expect(response).to redirect_to("/error_dashboard/errors/diagnostic_dumps")
        follow_redirect!
        expect(response.body).to include("Failed to capture diagnostic dump")
      end
    end

    context "authentication" do
      before { RailsErrorDashboard.configuration.enable_diagnostic_dump = true }

      it "requires authentication" do
        RailsErrorDashboard.configuration.authenticate_with = nil

        post "/error_dashboard/errors/create_diagnostic_dump"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
