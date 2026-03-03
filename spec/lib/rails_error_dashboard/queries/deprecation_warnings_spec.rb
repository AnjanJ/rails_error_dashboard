# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::DeprecationWarnings do
  def breadcrumbs_json(*crumbs)
    crumbs.to_json
  end

  def deprecation_crumb(message, caller_source: nil)
    crumb = { "c" => "deprecation", "m" => message }
    crumb["meta"] = { "caller" => caller_source } if caller_source
    crumb
  end

  def sql_crumb(message)
    { "c" => "sql", "m" => message, "d" => 1.2 }
  end

  describe ".call" do
    it "returns empty deprecations when no errors exist" do
      result = described_class.call(30)
      expect(result[:deprecations]).to eq([])
    end

    it "returns empty deprecations when errors have no breadcrumbs" do
      create(:error_log, breadcrumbs: nil, occurred_at: 1.day.ago)
      result = described_class.call(30)
      expect(result[:deprecations]).to eq([])
    end

    it "extracts deprecation crumbs from breadcrumbs" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          deprecation_crumb("Using `before_filter` is deprecated", caller_source: "app/controllers/users_controller.rb:5"),
          sql_crumb("SELECT * FROM users")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:deprecations].size).to eq(1)
      expect(result[:deprecations].first[:message]).to eq("Using `before_filter` is deprecated")
      expect(result[:deprecations].first[:source]).to eq("app/controllers/users_controller.rb:5")
      expect(result[:deprecations].first[:count]).to eq(1)
    end

    it "aggregates same deprecation across multiple errors" do
      msg = "ActionView::Base.field_error_proc is deprecated"
      3.times do
        create(:error_log,
          breadcrumbs: breadcrumbs_json(
            deprecation_crumb(msg, caller_source: "app/views/form.erb:10")
          ),
          occurred_at: 1.day.ago)
      end

      result = described_class.call(30)
      expect(result[:deprecations].size).to eq(1)
      expect(result[:deprecations].first[:count]).to eq(3)
      expect(result[:deprecations].first[:error_ids].size).to eq(3)
    end

    it "deduplicates error_ids when same error has duplicate deprecation crumbs" do
      error = create(:error_log,
        breadcrumbs: breadcrumbs_json(
          deprecation_crumb("Deprecated method called"),
          deprecation_crumb("Deprecated method called")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:deprecations].first[:count]).to eq(2)
      expect(result[:deprecations].first[:error_ids]).to eq([ error.id ])
    end

    it "groups by message + source combination" do
      msg = "render :text is deprecated"
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          deprecation_crumb(msg, caller_source: "app/controllers/a.rb:1")
        ),
        occurred_at: 1.day.ago)
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          deprecation_crumb(msg, caller_source: "app/controllers/b.rb:2")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:deprecations].size).to eq(2)
    end

    it "sorts by count descending" do
      3.times do
        create(:error_log,
          breadcrumbs: breadcrumbs_json(deprecation_crumb("High frequency warning")),
          occurred_at: 1.day.ago)
      end
      create(:error_log,
        breadcrumbs: breadcrumbs_json(deprecation_crumb("Low frequency warning")),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:deprecations].first[:message]).to eq("High frequency warning")
      expect(result[:deprecations].last[:message]).to eq("Low frequency warning")
    end

    it "respects time range" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(deprecation_crumb("Old warning")),
        occurred_at: 40.days.ago)
      create(:error_log,
        breadcrumbs: breadcrumbs_json(deprecation_crumb("Recent warning")),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:deprecations].size).to eq(1)
      expect(result[:deprecations].first[:message]).to eq("Recent warning")
    end

    it "filters by application_id" do
      app1 = create(:application, name: "App1")
      app2 = create(:application, name: "App2")

      create(:error_log,
        application: app1,
        breadcrumbs: breadcrumbs_json(deprecation_crumb("App1 warning")),
        occurred_at: 1.day.ago)
      create(:error_log,
        application: app2,
        breadcrumbs: breadcrumbs_json(deprecation_crumb("App2 warning")),
        occurred_at: 1.day.ago)

      result = described_class.call(30, application_id: app1.id)
      expect(result[:deprecations].size).to eq(1)
      expect(result[:deprecations].first[:message]).to eq("App1 warning")
    end

    it "handles malformed JSON breadcrumbs gracefully" do
      create(:error_log,
        breadcrumbs: "not valid json {{{",
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:deprecations]).to eq([])
    end

    it "tracks last_seen timestamp" do
      freeze_time do
        create(:error_log,
          breadcrumbs: breadcrumbs_json(deprecation_crumb("Warning")),
          occurred_at: 5.days.ago)
        create(:error_log,
          breadcrumbs: breadcrumbs_json(deprecation_crumb("Warning")),
          occurred_at: 1.day.ago)

        result = described_class.call(30)
        expect(result[:deprecations].first[:last_seen]).to eq(1.day.ago)
      end
    end

    it "sets source to Unknown when caller is absent" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(deprecation_crumb("No source warning")),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:deprecations].first[:source]).to eq("Unknown")
    end

    it "ignores non-deprecation breadcrumbs" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          sql_crumb("SELECT 1"),
          { "c" => "controller", "m" => "UsersController#index" }
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:deprecations]).to eq([])
    end
  end
end
