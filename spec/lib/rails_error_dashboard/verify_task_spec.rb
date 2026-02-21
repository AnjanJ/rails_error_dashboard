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
