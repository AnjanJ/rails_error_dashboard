# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Subscribers::BreadcrumbSubscriber do
  let(:collector) { RailsErrorDashboard::Services::BreadcrumbCollector }

  before do
    RailsErrorDashboard.configuration.enable_breadcrumbs = true
    collector.init_buffer
  end

  after do
    described_class.unsubscribe!
    collector.clear_buffer
    RailsErrorDashboard.reset_configuration!
  end

  describe ".subscribe!" do
    it "registers all expected event subscribers" do
      subscriptions = described_class.subscribe!
      expect(subscriptions).to be_an(Array)
      expect(subscriptions.size).to eq(6)
    end

    it "stores subscriptions for later cleanup" do
      described_class.subscribe!
      expect(described_class.subscriptions).not_to be_empty
    end
  end

  describe ".unsubscribe!" do
    it "removes all subscriptions" do
      described_class.subscribe!
      expect(described_class.subscriptions).not_to be_empty

      described_class.unsubscribe!
      expect(described_class.subscriptions).to be_empty
    end
  end

  describe "sql.active_record subscriber" do
    before { described_class.subscribe! }

    it "adds sql breadcrumb with query and duration" do
      ActiveSupport::Notifications.instrument("sql.active_record", {
        sql: "SELECT * FROM users WHERE id = 1",
        name: "User Load",
        duration: 1.5
      }) { }

      breadcrumbs = collector.harvest
      sql_crumbs = breadcrumbs.select { |c| c[:c] == "sql" }
      expect(sql_crumbs).not_to be_empty

      crumb = sql_crumbs.last
      expect(crumb[:m]).to include("SELECT * FROM users")
      expect(crumb[:d]).to be_a(Float)
    end

    it "skips SCHEMA queries" do
      ActiveSupport::Notifications.instrument("sql.active_record", {
        sql: "SELECT version()",
        name: "SCHEMA"
      }) { }

      breadcrumbs = collector.harvest
      expect(breadcrumbs.select { |c| c[:c] == "sql" }).to be_empty
    end

    it "skips internal gem queries" do
      ActiveSupport::Notifications.instrument("sql.active_record", {
        sql: "SELECT * FROM rails_error_dashboard_error_logs",
        name: "RailsErrorDashboard::ErrorLog Load"
      }) { }

      breadcrumbs = collector.harvest
      expect(breadcrumbs.select { |c| c[:c] == "sql" }).to be_empty
    end

    it "truncates long SQL queries to 200 chars" do
      long_sql = "SELECT " + "column_name, " * 50 + "id FROM users"
      ActiveSupport::Notifications.instrument("sql.active_record", {
        sql: long_sql,
        name: "User Load"
      }) { }

      breadcrumbs = collector.harvest
      sql_crumbs = breadcrumbs.select { |c| c[:c] == "sql" }
      expect(sql_crumbs.last[:m].length).to be <= 200
    end
  end

  describe "process_action.action_controller subscriber" do
    before { described_class.subscribe! }

    it "adds controller breadcrumb" do
      ActiveSupport::Notifications.instrument("process_action.action_controller", {
        controller: "UsersController",
        action: "show",
        status: 200,
        format: "html"
      }) { }

      breadcrumbs = collector.harvest
      ctrl_crumbs = breadcrumbs.select { |c| c[:c] == "controller" }
      expect(ctrl_crumbs).not_to be_empty
      expect(ctrl_crumbs.last[:m]).to eq("UsersController#show")
    end
  end

  describe "cache subscribers" do
    before { described_class.subscribe! }

    it "adds cache read breadcrumb" do
      ActiveSupport::Notifications.instrument("cache_read.active_support", {
        key: "users/1",
        hit: true
      }) { }

      breadcrumbs = collector.harvest
      cache_crumbs = breadcrumbs.select { |c| c[:c] == "cache" }
      expect(cache_crumbs).not_to be_empty
      expect(cache_crumbs.last[:m]).to include("cache read:")
      expect(cache_crumbs.last[:m]).to include("users/1")
    end

    it "adds cache write breadcrumb" do
      ActiveSupport::Notifications.instrument("cache_write.active_support", {
        key: "users/1"
      }) { }

      breadcrumbs = collector.harvest
      cache_crumbs = breadcrumbs.select { |c| c[:c] == "cache" }
      expect(cache_crumbs).not_to be_empty
      expect(cache_crumbs.last[:m]).to include("cache write:")
    end
  end

  describe "perform.active_job subscriber" do
    before { described_class.subscribe! }

    it "adds job breadcrumb" do
      job_double = double("SendEmailJob", class: double(name: "SendEmailJob"), job_id: "abc-123")
      allow(job_double).to receive_messages(provider_job_id: nil, queue_name: "default")
      ActiveSupport::Notifications.instrument("perform.active_job", {
        job: job_double
      }) { }

      breadcrumbs = collector.harvest
      job_crumbs = breadcrumbs.select { |c| c[:c] == "job" }
      expect(job_crumbs).not_to be_empty
      expect(job_crumbs.last[:m]).to eq("SendEmailJob")
    end
  end

  describe "deliver.action_mailer subscriber" do
    before { described_class.subscribe! }

    it "adds mailer breadcrumb" do
      ActiveSupport::Notifications.instrument("deliver.action_mailer", {
        mailer: "UserMailer",
        to: [ "user@example.com" ]
      }) { }

      breadcrumbs = collector.harvest
      mailer_crumbs = breadcrumbs.select { |c| c[:c] == "mailer" }
      expect(mailer_crumbs).not_to be_empty
      expect(mailer_crumbs.last[:m]).to include("UserMailer")
      expect(mailer_crumbs.last[:m]).to include("user@example.com")
    end
  end

  describe "safety" do
    before { described_class.subscribe! }

    it "does not add breadcrumbs when buffer is nil" do
      collector.clear_buffer

      ActiveSupport::Notifications.instrument("sql.active_record", {
        sql: "SELECT 1",
        name: "Test"
      }) { }

      collector.init_buffer
      breadcrumbs = collector.harvest
      expect(breadcrumbs).to be_empty
    end

    it "never raises from subscribers" do
      # Even with broken payload
      expect {
        ActiveSupport::Notifications.instrument("sql.active_record", {
          sql: nil,
          name: nil
        }) { }
      }.not_to raise_error
    end
  end
end
