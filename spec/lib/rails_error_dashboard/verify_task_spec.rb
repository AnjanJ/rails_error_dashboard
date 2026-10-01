# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "error_dashboard:verify rake task" do
  before(:all) do
    Rails.application.load_tasks
  end

  let!(:application) { create(:application) }
  let(:task) { Rake::Task["error_dashboard:verify"] }

  before do
    task.reenable
  end

  describe "output" do
    it "prints the verification header" do
      output = capture_stdout { task.invoke }
      expect(output).to include("RAILS ERROR DASHBOARD - SETUP VERIFICATION")
    end

    it "checks configuration" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Checking configuration...")
      expect(output).to include("OK")
    end

    it "reports database mode" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Database mode...")
    end

    it "checks database connection" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Database connection...")
      expect(output).to include("OK")
    end

    it "checks required tables" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Required tables...")
      expect(output).to include("6 tables found")
    end

    it "checks application registration" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Application registration...")
    end

    it "checks error data count" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Error data...")
    end

    it "checks authentication credentials" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Authentication...")
    end

    it "prints summary results" do
      output = capture_stdout { task.invoke }
      expect(output).to match(/Results: \d+ passed, \d+ failed, \d+ warnings/)
    end
  end

  describe "with default credentials" do
    it "warns about default credentials in non-production" do
      output = capture_stdout { task.invoke }
      expect(output).to include("default credentials")
    end
  end

  describe "with custom authenticate_with" do
    around do |example|
      original = RailsErrorDashboard.configuration.authenticate_with
      RailsErrorDashboard.configuration.authenticate_with = -> { true }
      example.run
      RailsErrorDashboard.configuration.authenticate_with = original
    end

    it "reports custom authentication as OK" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Authentication...")
      expect(output).to include("custom authentication")
    end
  end

  describe "with custom credentials" do
    around do |example|
      original_user = RailsErrorDashboard.configuration.dashboard_username
      original_pass = RailsErrorDashboard.configuration.dashboard_password
      RailsErrorDashboard.configuration.dashboard_username = "custom_user"
      RailsErrorDashboard.configuration.dashboard_password = "custom_pass"
      example.run
      RailsErrorDashboard.configuration.dashboard_username = original_user
      RailsErrorDashboard.configuration.dashboard_password = original_pass
    end

    it "reports custom credentials as OK" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Authentication...")
      expect(output).to include("custom credentials")
    end
  end

  # The task used to compare values against gandalf/youshallnotpass and check
  # only production?, so a blank password was reported as custom credentials
  # and staging never failed. It now follows the boot check's rule.
  describe "with credentials the boot check refuses" do
    around do |example|
      config = RailsErrorDashboard.configuration
      original_user = config.dashboard_username
      original_pass = config.dashboard_password
      example.run
    ensure
      config.dashboard_username = original_user
      config.dashboard_password = original_pass
    end

    it "does not report a blank password as custom credentials" do
      RailsErrorDashboard.configuration.dashboard_username = "custom_user"
      RailsErrorDashboard.configuration.dashboard_password = ""

      output = capture_stdout { task.invoke }
      expect(output).not_to include("custom credentials")
      expect(output).to include("blank credentials")
    end

    # It used to say "OK (blank credentials - change before production)" while
    # every login was being denied.
    it "warns that a blank credential denies every login in development and test" do
      RailsErrorDashboard.configuration.dashboard_username = "custom_user"
      RailsErrorDashboard.configuration.dashboard_password = ""

      output = capture_stdout { task.invoke }

      expect(output).to include("WARNING - blank credentials: every login is denied")
    end

    it "fails the check on the published password outside development and test" do
      RailsErrorDashboard.configuration.dashboard_username = "custom_user"
      RailsErrorDashboard.configuration.dashboard_password = "youshallnotpass"
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("staging"))

      output = capture_stdout { task.invoke }
      expect(output).to include("WARNING - default credentials outside development and test!")
    end

    # The boot check allows this (the live demo runs on it), but it is still the
    # published password, so it must not read as custom credentials either.
    it "warns, without failing, when ERROR_DASHBOARD_PASSWORD explicitly sets the published password" do
      saved = ENV.to_h.slice("ERROR_DASHBOARD_PASSWORD")
      ENV["ERROR_DASHBOARD_PASSWORD"] = "youshallnotpass"
      RailsErrorDashboard.configuration.dashboard_password = "youshallnotpass"
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("staging"))

      output = capture_stdout { task.invoke }
      expect(output).to include("OK (the published default password, set explicitly by ERROR_DASHBOARD_PASSWORD)")
      expect(output).not_to include("custom credentials")
    ensure
      ENV.delete("ERROR_DASHBOARD_PASSWORD")
      saved.each { |k, v| ENV[k] = v }
    end
  end

  # With a separate database, a missing database.yml entry for this environment
  # makes the engine skip connects_to: RED then uses the main database, and
  # unless that has RED's tables no error is recorded. verify has to say so.
  describe "error database entry check" do
    before do
      RailsErrorDashboard.configuration.use_separate_database = true
      RailsErrorDashboard.configuration.database = :error_dashboard
    end

    after { RailsErrorDashboard.reset_configuration! }

    it "fails when config/database.yml has no entry for this environment" do
      output = capture_stdout { task.invoke }

      expect(output).to include("Error database entry... FAILED")
      expect(output).to include("no 'error_dashboard' entry for the 'test' environment")
      expect(output).to include("Status: NEEDS ATTENTION")
    end

    it "passes when the entry exists" do
      entry = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, name: "error_dashboard")
      allow(ActiveRecord::Base.configurations).to receive(:configs_for).and_call_original
      allow(ActiveRecord::Base.configurations).to receive(:configs_for).with(env_name: "test").and_return([ entry ])

      output = capture_stdout { task.invoke }

      expect(output).to include("Error database entry... OK")
    end

    it "isn't checked without a separate database" do
      RailsErrorDashboard.configuration.use_separate_database = false

      output = capture_stdout { task.invoke }

      expect(output).not_to include("Error database entry...")
    end
  end

  # json 3.0 breaks Rails before 8.1.4 / 7.2.4: dashboard pages return 500 and
  # captures can fail, with no error message. verify is the place to say so.
  describe "json gem check" do
    def with_json(version)
      specs = Gem.loaded_specs.merge("json" => instance_double(Gem::Specification, version: Gem::Version.new(version)))
      allow(Gem).to receive(:loaded_specs).and_return(specs)
    end

    it "warns when json 3 runs on a Rails it breaks" do
      with_json("3.0.2")
      allow(Rails).to receive(:version).and_return("8.0.4")

      output = capture_stdout { task.invoke }

      expect(output).to include("json gem... WARNING")
      expect(output).to include('gem "json", "< 3"')
    end

    it "is OK when json 3 runs on a fixed Rails" do
      with_json("3.0.2")
      allow(Rails).to receive(:version).and_return("8.1.4")

      output = capture_stdout { task.invoke }

      expect(output).to include("json gem... OK")
    end

    it "says nothing with json 2" do
      with_json("2.21.2")

      output = capture_stdout { task.invoke }

      expect(output).not_to include("json gem...")
    end
  end

  describe "retention policy check" do
    it "shows OK with retention_days when configured" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Data retention...")
      expect(output).to include("OK (90 days)")
    end

    context "when retention_days is nil" do
      around do |example|
        original = RailsErrorDashboard.configuration.retention_days
        RailsErrorDashboard.configuration.retention_days = nil
        example.run
        RailsErrorDashboard.configuration.retention_days = original
      end

      it "shows OK with no limit in development" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        output = capture_stdout { task.invoke }
        expect(output).to include("Data retention...")
        expect(output).to include("OK (no limit")
      end

      it "shows WARNING in production" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        output = capture_stdout { task.invoke }
        expect(output).to include("Data retention...")
        expect(output).to include("WARNING")
      end
    end

    context "when retention_days is custom value" do
      around do |example|
        original = RailsErrorDashboard.configuration.retention_days
        RailsErrorDashboard.configuration.retention_days = 365
        example.run
        RailsErrorDashboard.configuration.retention_days = original
      end

      it "shows the custom retention period" do
        output = capture_stdout { task.invoke }
        expect(output).to include("OK (365 days)")
      end
    end
  end

  describe "with existing errors" do
    let!(:error_log) do
      create(:error_log, application: application, resolved: false)
    end

    it "shows error count" do
      output = capture_stdout { task.invoke }
      expect(output).to match(/\d+ total errors/)
    end
  end

  describe "database mode reporting" do
    context "when using shared database" do
      it "reports SHARED mode" do
        output = capture_stdout { task.invoke }
        expect(output).to include("SHARED")
      end
    end

    context "when use_separate_database is true" do
      around do |example|
        original = RailsErrorDashboard.configuration.use_separate_database
        RailsErrorDashboard.configuration.use_separate_database = true
        example.run
        RailsErrorDashboard.configuration.use_separate_database = original
      end

      it "reports SEPARATE mode" do
        output = capture_stdout { task.invoke }
        expect(output).to include("SEPARATE")
      end
    end
  end

  # A config/queue.yml with workers and no dispatchers runs no dispatcher, so no
  # delayed job runs. The retired rails_error_dashboard:solid_queue generator
  # wrote one, and verify is how existing installs find out. It checks whenever
  # Solid Queue is loaded, not only when it is the current adapter: Rails 8 sets
  # :solid_queue in production only, and verify is usually run locally (this
  # suite's adapter is :test).
  describe "Solid Queue config check" do
    let(:fixtures) { File.expand_path("../../fixtures/solid_queue", __dir__) }
    let(:check) { RailsErrorDashboard::Services::SolidQueueConfigCheck }

    def with_config(name)
      allow(check).to receive(:config_path).and_return(Pathname(File.join(fixtures, name)))
    end

    context "when Solid Queue is loaded" do
      before { stub_const("SolidQueue", Module.new) }

      it "fails the config the old generator wrote, in every environment, whatever the current adapter" do
        with_config("red_generator_queue.yml")
        allow(check).to receive(:app_environments).and_return(%w[development production])

        output = capture_stdout { task.invoke }

        expect(output).to include("Solid Queue config... FAILED")
        expect(output).to match(/development: .*no dispatcher/)
        expect(output).to match(/production: .*no dispatcher/)
      end

      # Whoever sees this already uses Solid Queue, and its installer would
      # rewrite production.rb to use a separate queue database (1.7.0).
      it "gives a fix that edits the file, not one that re-runs Solid Queue's installer" do
        with_config("red_generator_queue.yml")

        output = capture_stdout { task.invoke }

        expect(output).not_to include("solid_queue:install")
        expect(output).to include("dispatchers:")
        expect(output).to include(check::GUIDE_URL)
      end

      it "passes Solid Queue's own config" do
        with_config("solid_queue_install_queue.yml")

        output = capture_stdout { task.invoke }

        expect(output).to include("Solid Queue config... OK")
      end

      it "says nothing when the app has no config file" do
        with_config("does_not_exist.yml")

        output = capture_stdout { task.invoke }

        expect(output).not_to include("Solid Queue config")
      end
    end

    it "says nothing when Solid Queue is not loaded" do
      hide_const("SolidQueue") if defined?(SolidQueue)
      with_config("red_generator_queue.yml")

      output = capture_stdout { task.invoke }

      expect(output).not_to include("Solid Queue config")
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end

RSpec.describe "error_dashboard:retention_cleanup rake task" do
  before(:all) do
    Rails.application.load_tasks
  end

  let(:task) { Rake::Task["error_dashboard:retention_cleanup"] }

  before do
    task.reenable
  end

  describe "output" do
    it "prints the retention cleanup header" do
      allow($stdin).to receive(:gets).and_return("n\n")
      output = capture_stdout { task.invoke }
      expect(output).to include("RETENTION CLEANUP")
    end

    context "when retention_days is nil" do
      around do |example|
        original = RailsErrorDashboard.configuration.retention_days
        RailsErrorDashboard.configuration.retention_days = nil
        example.run
        RailsErrorDashboard.configuration.retention_days = original
      end

      it "shows not configured message" do
        output = capture_stdout { task.invoke }
        expect(output).to include("retention_days is not configured")
      end
    end

    context "when no errors to delete" do
      it "shows no errors message" do
        output = capture_stdout { task.invoke }
        expect(output).to include("No errors unseen for more than")
      end
    end

    context "when there are expired errors" do
      let!(:old_error) { create(:error_log, occurred_at: 91.days.ago) }

      it "shows the count of errors to delete" do
        allow($stdin).to receive(:gets).and_return("n\n")
        output = capture_stdout { task.invoke }
        expect(output).to include("Errors to delete: 1")
      end

      it "cancels when user says no" do
        allow($stdin).to receive(:gets).and_return("n\n")
        output = capture_stdout { task.invoke }
        expect(output).to include("Cleanup cancelled")
        expect(RailsErrorDashboard::ErrorLog.exists?(old_error.id)).to be true
      end

      it "deletes errors when user confirms" do
        allow($stdin).to receive(:gets).and_return("y\n")
        output = capture_stdout { task.invoke }
        expect(output).to include("Retention cleanup complete!")
        expect(RailsErrorDashboard::ErrorLog.exists?(old_error.id)).to be false
      end
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end

RSpec.describe "error_dashboard:list_applications rake task" do
  before(:all) do
    Rails.application.load_tasks
  end

  let(:task) { Rake::Task["error_dashboard:list_applications"] }

  before do
    task.reenable
  end

  describe "with no applications" do
    it "shows no applications message" do
      output = capture_stdout { task.invoke }
      expect(output).to include("No applications registered")
    end
  end

  describe "with registered applications" do
    let!(:app1) { create(:application, name: "BlogApi") }
    let!(:app2) { create(:application, name: "AdminPanel") }
    let!(:error1) { create(:error_log, application: app1, resolved: false) }
    let!(:error2) { create(:error_log, application: app1, resolved: true, resolved_at: Time.current) }
    let!(:error3) { create(:error_log, application: app2, resolved: false) }

    it "lists all applications" do
      output = capture_stdout { task.invoke }
      expect(output).to include("BlogApi")
      expect(output).to include("AdminPanel")
    end

    it "shows summary statistics" do
      output = capture_stdout { task.invoke }
      expect(output).to include("Total Applications: 2")
      expect(output).to include("Total Errors:")
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
