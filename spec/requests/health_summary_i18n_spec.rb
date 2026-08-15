# frozen_string_literal: true

require "rails_helper"

# The six health-summary pages (database, LLM, cache, job, ActionCable,
# ActiveStorage — P2-T5). Pre-existing specs already pin the bulk of the
# rendered strings byte-for-byte (extraction preserved the English text
# verbatim), so this spec focuses on what those specs can't see: the shared
# days_filter keys actually being shared, the non-mechanical interpolations
# (the database adapter name landing in an _html key, the per-adapter job
# sentences), and that the empty-state "how it works" lists actually moved to
# the locale file rather than staying hardcoded.
RSpec.describe "Health summary translations", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_system_health = false
    RailsErrorDashboard.configuration.enable_breadcrumbs = false
    RailsErrorDashboard.configuration.enable_llm_observability = false
    RailsErrorDashboard.configuration.enable_actioncable_tracking = false
    RailsErrorDashboard.configuration.enable_activestorage_tracking = false
  end

  describe "shared days_filter keys" do
    it "renders the same day-range labels on every health page" do
      RailsErrorDashboard.configuration.enable_system_health = true

      get "/error_dashboard/errors/database_health_summary", params: { days: 30 }
      expect(response.body).to include("7 Days").and include("30 Days").and include("90 Days")

      get "/error_dashboard/errors/job_health_summary", params: { days: 30 }
      expect(response.body).to include("7 Days").and include("30 Days").and include("90 Days")
    end
  end

  describe "database health — non-PostgreSQL adapter banner" do
    before { RailsErrorDashboard.configuration.enable_system_health = true }

    it "interpolates the detected adapter name into the _html key" do
      allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("SQLite")

      get "/error_dashboard/errors/database_health_summary"

      expect(response.body).to include("Non-PostgreSQL adapter detected (SQLite).")
    end

    it "escapes an adapter name that contains markup rather than rendering it raw" do
      allow(ActiveRecord::Base.connection).to receive(:adapter_name)
        .and_return("<script>alert(1)</script>")

      get "/error_dashboard/errors/database_health_summary"

      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(response.body).to include("&lt;script&gt;")
    end
  end

  describe "database health — never-vacuumed fallback" do
    before { RailsErrorDashboard.configuration.enable_system_health = true }

    it "shows the localized fallback instead of a hardcoded literal" do
      allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("PostgreSQL")
      inspector_result = {
        postgresql: true,
        adapter: "PostgreSQL",
        tables: [
          { name: "widgets", gem_table: false, estimated_rows: 10, total_bytes: 1024,
            seq_scan: 0, idx_scan: 0, dead_tuples: 0, last_autovacuum: nil }
        ],
        connection_pool: nil,
        unused_indexes: [],
        activity: nil
      }
      allow(RailsErrorDashboard::Services::DatabaseHealthInspector).to receive(:call)
        .and_return(inspector_result)

      get "/error_dashboard/errors/database_health_summary"

      expect(response.body).to include("Never")
    end
  end

  describe "job health — per-adapter stat sentences" do
    before { RailsErrorDashboard.configuration.enable_system_health = true }

    it "renders the sidekiq-specific other-stats sentence with real counts" do
      create(:error_log,
        application: application,
        system_health: {
          "job_queue" => {
            "adapter" => "sidekiq", "enqueued" => 42, "failed" => 5,
            "dead" => 2, "retry" => 1, "workers" => 10
          }
        }.to_json,
        occurred_at: 1.day.ago)

      get "/error_dashboard/errors/job_health_summary"

      expect(response.body).to include("42 enqueued")
      expect(response.body).to include("dead: 2, retry: 1, workers: 10")
    end

    it "renders the solid_queue-specific other-stats sentence with real counts" do
      create(:error_log,
        application: application,
        system_health: {
          "job_queue" => {
            "adapter" => "solid_queue", "ready" => 7, "failed" => 0,
            "claimed" => 3, "blocked" => 1, "scheduled" => 4
          }
        }.to_json,
        occurred_at: 1.day.ago)

      get "/error_dashboard/errors/job_health_summary"

      expect(response.body).to include("7 ready")
      expect(response.body).to include("claimed: 3, blocked: 1, scheduled: 4")
    end

    it "renders the good_job-specific other-stats sentence with real counts" do
      create(:error_log,
        application: application,
        system_health: {
          "job_queue" => {
            "adapter" => "good_job", "queued" => 9, "failed" => 0, "finished" => 20
          }
        }.to_json,
        occurred_at: 1.day.ago)

      get "/error_dashboard/errors/job_health_summary"

      expect(response.body).to include("9 queued")
      expect(response.body).to include("finished: 20")
    end
  end

  describe "LLM health — interpolated stat and count labels" do
    before do
      RailsErrorDashboard.configuration.enable_breadcrumbs = true
      RailsErrorDashboard.configuration.enable_llm_observability = true
    end

    def llm_crumb(status: "success", error_class: nil)
      {
        "c" => "llm",
        "m" => "anthropic · claude-3-5-sonnet",
        "meta" => { "provider" => "anthropic", "model" => "claude-3-5-sonnet",
                    "status" => status, "error_class" => error_class }.compact
      }
    end

    it "interpolates the error rate percentage into the stat tile label" do
      crumbs = ([ llm_crumb(status: "success") ] * 9) +
               [ llm_crumb(status: "error", error_class: "Anthropic::RateLimitError") ]
      create(:error_log, application: application, breadcrumbs: crumbs.to_json, occurred_at: 1.day.ago)

      get "/error_dashboard/errors/llm_health_summary"

      expect(response.body).to include("Errors with LLM (10.0%)")
    end

    it "interpolates the failed-call count next to the model row" do
      crumbs = ([ llm_crumb(status: "success") ] * 4) +
               [ llm_crumb(status: "error", error_class: "Anthropic::RateLimitError") ]
      create(:error_log, application: application, breadcrumbs: crumbs.to_json, occurred_at: 1.day.ago)

      get "/error_dashboard/errors/llm_health_summary"

      expect(response.body).to include("1 failed")
    end

    it "renders the disabled-feature copy from the locale, not a literal" do
      RailsErrorDashboard.configuration.enable_llm_observability = false

      get "/error_dashboard/errors/llm_health_summary"

      expect(response.body).to include("LLM Observability Not Enabled")
      expect(response.body).to include("To see per-model LLM stats here, enable LLM observability and breadcrumbs.")
    end
  end

  describe "cache health — empty-state how-it-works list" do
    before { RailsErrorDashboard.configuration.enable_breadcrumbs = true }

    it "renders all four steps from the locale file" do
      get "/error_dashboard/errors/cache_health_summary"

      expect(response.body).to include("How cache tracking works:")
      expect(response.body).to include("This page shows cache performance per-error, sorted worst-first")
    end
  end

  describe "ActionCable health — empty-state copy" do
    before do
      RailsErrorDashboard.configuration.enable_actioncable_tracking = true
      RailsErrorDashboard.configuration.enable_breadcrumbs = true
    end

    it "renders the translated empty state" do
      get "/error_dashboard/errors/actioncable_health_summary"

      expect(response.body).to include("No ActionCable Events Found")
      expect(response.body).to include("How ActionCable tracking works:")
    end
  end

  describe "ActiveStorage health — empty-state copy" do
    before do
      RailsErrorDashboard.configuration.enable_activestorage_tracking = true
      RailsErrorDashboard.configuration.enable_breadcrumbs = true
    end

    it "renders the translated empty state" do
      get "/error_dashboard/errors/activestorage_health_summary"

      expect(response.body).to include("No ActiveStorage Events Found")
      expect(response.body).to include("How ActiveStorage tracking works:")
    end
  end
end
