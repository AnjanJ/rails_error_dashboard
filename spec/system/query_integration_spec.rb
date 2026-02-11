# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Query Integration", type: :system do
  let!(:application) { create(:application) }

  describe "CriticalAlerts on overview page" do
    context "when critical/high priority errors exist within the last hour" do
      let!(:critical_error) do
        create(:error_log,
          application: application,
          error_type: "DatabaseConnectionError",
          message: "Connection pool exhausted",
          priority_level: 4,
          status: "new",
          resolved: false,
          resolved_at: nil,
          occurred_at: 10.minutes.ago)
      end

      it "displays the critical alerts section" do
        visit_dashboard
        wait_for_page_load
        expect(page).to have_css(".alert-danger", text: "Critical/High Error")
        expect(page).to have_content("DatabaseConnectionError")
        expect(page).to have_content("Connection pool exhausted")
      end

      it "links critical alert to error detail page" do
        visit_dashboard
        wait_for_page_load
        within(".alert-danger") do
          find("a", text: "DatabaseConnectionError").click
        end
        wait_for_page_load
        expect(page).to have_content("Connection pool exhausted")
      end
    end

    context "when no critical errors exist" do
      let!(:low_priority_error) do
        create(:error_log,
          application: application,
          error_type: "MinorWarning",
          message: "Deprecation notice",
          priority_level: 0,
          status: "new",
          resolved: false,
          resolved_at: nil,
          occurred_at: 10.minutes.ago)
      end

      it "does not display the critical alerts section" do
        visit_dashboard
        wait_for_page_load
        expect(page).not_to have_css(".alert-danger", text: "Critical/High Error")
      end
    end

    context "when critical errors are resolved" do
      let!(:resolved_critical) do
        create(:error_log,
          application: application,
          error_type: "ResolvedCritical",
          message: "Already fixed",
          priority_level: 4,
          status: "resolved",
          resolved: true,
          resolved_at: 5.minutes.ago,
          occurred_at: 30.minutes.ago)
      end

      it "does not display resolved critical errors in the alerts section" do
        visit_dashboard
        wait_for_page_load
        # The critical alerts section should not appear at all
        expect(page).not_to have_css(".alert-danger", text: "Critical/High Error")
      end
    end

    context "when critical errors are older than 1 hour" do
      let!(:old_critical) do
        create(:error_log,
          application: application,
          error_type: "OldCritical",
          message: "Stale error",
          priority_level: 4,
          status: "new",
          resolved: false,
          resolved_at: nil,
          occurred_at: 2.hours.ago)
      end

      it "does not display old critical errors in the alerts section" do
        visit_dashboard
        wait_for_page_load
        # The critical alerts section should not appear at all
        expect(page).not_to have_css(".alert-danger", text: "Critical/High Error")
      end
    end
  end

  describe "FilterOptions assignees on errors index" do
    context "when errors have assignees" do
      let!(:assigned_error) do
        create(:error_log,
          application: application,
          error_type: "AssignedError",
          message: "Someone is on it",
          assigned_to: "aragorn",
          assigned_at: 1.hour.ago)
      end

      let!(:unassigned_error) do
        create(:error_log,
          application: application,
          error_type: "UnassignedError",
          message: "Nobody owns this",
          assigned_to: nil)
      end

      it "includes assignees in the filter dropdown" do
        visit_dashboard("/errors")
        wait_for_page_load
        # The assignee_name_filter is hidden by default; check the select exists in the DOM
        expect(page).to have_css("#assignee_name_filter select", visible: :all)
        # Verify "aragorn" is an option in the hidden select
        expect(page).to have_css("#assignee_name_filter option[value='aragorn']", visible: :all)
      end

      it "shows assignee dropdown when Assigned filter is selected" do
        visit_dashboard("/errors")
        wait_for_page_load
        # Select "Assigned" from the assignment filter
        select "Assigned", from: "assigned_to_filter"
        # The assignee name filter should become visible
        expect(page).to have_css("#assignee_name_filter", visible: true)
        # And contain our assignee
        within("#assignee_name_filter") do
          expect(page).to have_css("option[value='aragorn']")
        end
      end
    end

    context "when no errors are assigned" do
      let!(:unassigned_error) do
        create(:error_log,
          application: application,
          error_type: "UnassignedError",
          message: "No owner",
          assigned_to: nil)
      end

      it "shows only the default empty-value option when no assignees exist" do
        visit_dashboard("/errors")
        wait_for_page_load
        # The hidden select should exist with just one option (the "All Assignees" default)
        select_element = find("#assignee_name_filter select", visible: :all)
        option_values = select_element.all("option", visible: :all).map { |o| o.value }
        expect(option_values).to eq([ "" ])
      end
    end

    context "when multiple assignees exist" do
      before do
        create(:error_log, application: application, assigned_to: "gandalf")
        create(:error_log, application: application, assigned_to: "aragorn")
        create(:error_log, application: application, assigned_to: "legolas")
        create(:error_log, application: application, assigned_to: "gandalf") # duplicate
      end

      it "shows distinct assignees sorted alphabetically" do
        visit_dashboard("/errors")
        wait_for_page_load
        # Use option values — hidden elements return empty text in headless Chrome
        select_element = find("#assignee_name_filter select", visible: :all)
        option_values = select_element.all("option", visible: :all).map { |o| o.value }
        # First option is "" (All Assignees default), then sorted unique names
        expect(option_values).to eq([ "", "aragorn", "gandalf", "legolas" ])
      end
    end
  end

  describe "Analytics page with PatternDetector integration" do
    context "when errors exist for analytics" do
      before do
        # Create errors with varied timestamps to exercise PatternDetector
        15.times do |i|
          create(:error_log,
            application: application,
            error_type: "RecurringError",
            message: "Keeps happening",
            occurred_at: i.days.ago,
            occurrence_count: 5 + i)
        end
        5.times do |i|
          create(:error_log,
            application: application,
            error_type: "RareError",
            message: "Seldom seen",
            occurred_at: (i * 3).days.ago,
            occurrence_count: 1)
        end
      end

      it "loads analytics page with recurring issues section" do
        visit_dashboard("/errors/analytics")
        wait_for_page_load
        expect(page).to have_content("Analytics")
        expect(page).to have_content("Recurring Issues")
      end

      it "displays resolution rate from analytics stats" do
        visit_dashboard("/errors/analytics")
        wait_for_page_load
        expect(page).to have_content("Resolution Rate")
      end

      it "displays errors by type breakdown" do
        visit_dashboard("/errors/analytics")
        wait_for_page_load
        expect(page).to have_content("RecurringError")
      end
    end

    context "with no errors" do
      it "loads analytics page without crashing" do
        visit_dashboard("/errors/analytics")
        wait_for_page_load
        expect(page).to have_content("Analytics")
      end
    end
  end

  describe "Command-driven workflow actions" do
    let!(:workflow_error) do
      create(:error_log,
        application: application,
        error_type: "WorkflowTestError",
        message: "Testing command write logic",
        status: "new",
        resolved: false,
        assigned_to: nil,
        snoozed_until: nil)
    end

    it "assign auto-transitions status to in_progress" do
      visit_error(workflow_error)
      wait_for_page_load

      assign_error_to("aragorn")
      wait_for_page_load

      # The status badge should show "In Progress" (auto-set by AssignError command)
      expect(page).to have_content("In Progress")
      expect(page).to have_content("aragorn")

      # Verify DB state
      workflow_error.reload
      expect(workflow_error.status).to eq("in_progress")
      expect(workflow_error.assigned_to).to eq("aragorn")
      expect(workflow_error.assigned_at).to be_present
    end

    it "unassign clears assignment fields in the database" do
      # Pre-assign via command
      RailsErrorDashboard::Commands::AssignError.call(workflow_error.id, assigned_to: "gandalf")

      visit_error(workflow_error)
      wait_for_page_load
      expect(page).to have_content("gandalf")

      unassign_error
      wait_for_page_load

      # Assign button should be back
      expect(page).to have_css("[data-bs-target='#assignModal']")

      # Verify DB state
      workflow_error.reload
      expect(workflow_error.assigned_to).to be_nil
      expect(workflow_error.assigned_at).to be_nil
    end

    it "snooze without reason does not create a comment" do
      visit_error(workflow_error)
      wait_for_page_load

      comment_count_before = workflow_error.comments.count

      snooze_error_for("1 hour")
      wait_for_page_load

      expect(page).to have_content("Snoozed")

      # No comment should have been created (reason was blank)
      workflow_error.reload
      expect(workflow_error.comments.count).to eq(comment_count_before)
      expect(workflow_error.snoozed_until).to be_present
    end

    it "snooze with reason creates a comment attributed to assignee" do
      # Pre-assign so comment is attributed to the assignee
      RailsErrorDashboard::Commands::AssignError.call(workflow_error.id, assigned_to: "legolas")

      visit_error(workflow_error)
      wait_for_page_load

      snooze_error_for("4 hours", reason: "Deploy pending")
      wait_for_page_load

      expect(page).to have_content("Snoozed")
      expect(page).to have_content("Deploy pending")

      # Verify comment was attributed to the assignee
      comment = workflow_error.comments.last
      expect(comment.author_name).to eq("legolas")
      expect(comment.body).to include("Snoozed for 4 hours")
    end

    it "unsnooze clears snoozed_until in the database" do
      # Pre-snooze via command
      RailsErrorDashboard::Commands::SnoozeError.call(workflow_error.id, hours: 8)

      visit_error(workflow_error)
      wait_for_page_load
      expect(page).to have_content("Snoozed")

      unsnooze_error
      wait_for_page_load

      expect(page).not_to have_css(".alert-warning", text: "Snoozed")

      # Verify DB state
      workflow_error.reload
      expect(workflow_error.snoozed_until).to be_nil
    end

    it "resolve sets resolved flag via Command" do
      # Move to in_progress first (required for valid transition path)
      RailsErrorDashboard::Commands::AssignError.call(workflow_error.id, assigned_to: "gandalf")

      visit_error(workflow_error)
      wait_for_page_load

      resolve_error(name: "gandalf", comment: "Root cause fixed")
      wait_for_page_load

      expect(page).to have_content("Resolved")

      # Verify DB state — ResolveError sets resolved flag and resolved_at
      workflow_error.reload
      expect(workflow_error.resolved).to be true
      expect(workflow_error.resolved_at).to be_present
      expect(workflow_error.resolved_by_name).to eq("gandalf")
      expect(workflow_error.resolution_comment).to eq("Root cause fixed")
    end
  end

  describe "Service-driven statistics on dashboard" do
    context "when spike detection uses StatisticalClassifier" do
      before do
        # Create a spike: many errors today, few on previous days
        # Need >2x average to trigger spike detection
        20.times do |i|
          create(:error_log,
            application: application,
            error_type: "SpikeTestError",
            message: "Spike test error",
            occurred_at: i.minutes.ago)
        end
        # Create 1 error per day for past 6 days (avg ~1/day, today has 20 = 20x)
        6.times do |i|
          create(:error_log,
            application: application,
            error_type: "SpikeTestError",
            message: "Normal baseline error",
            occurred_at: (i + 1).days.ago)
        end
      end

      it "displays spike alert with severity classified by service" do
        visit_dashboard("/errors")
        wait_for_page_load
        # Spike should be detected (20 today vs ~3.7 avg = ~5.4x = :high severity)
        expect(page).to have_css(".alert-warning")
        expect(page).to have_content("normal levels")
      end
    end

    context "when trend direction displays on overview" do
      before do
        # Create errors only today to get an "Increasing" trend
        5.times do |i|
          create(:error_log,
            application: application,
            error_type: "TrendTestError",
            message: "Trend test",
            occurred_at: i.minutes.ago)
        end
      end

      it "shows trend text on overview page" do
        visit_dashboard
        wait_for_page_load
        # The overview page should show a trend direction (Increasing, Decreasing, or Stable)
        expect(page).to have_content("Dashboard")
        # One of the trend texts should be present
        trend_shown = page.has_content?("Increasing") ||
                      page.has_content?("Decreasing") ||
                      page.has_content?("Stable")
        expect(trend_shown).to be true
      end
    end
  end

  describe "LogError service delegation (Phase 6)" do
    after { RailsErrorDashboard.reset_configuration! }

    context "when ErrorHashGenerator deduplicates errors" do
      it "groups errors with same normalized message into one row" do
        # Use LogError.call directly — it now delegates to ErrorHashGenerator
        error1 = RuntimeError.new("User 100 not found")
        error1.set_backtrace([ "#{Rails.root}/app/models/user.rb:5:in `find'" ])
        error2 = RuntimeError.new("User 999 not found")
        error2.set_backtrace([ "#{Rails.root}/app/models/user.rb:5:in `find'" ])

        RailsErrorDashboard::Commands::LogError.call(error1, { controller_name: "users", action_name: "show" })
        RailsErrorDashboard::Commands::LogError.call(error2, { controller_name: "users", action_name: "show" })

        visit_dashboard("/errors")
        wait_for_page_load

        # Both errors should be grouped under one row with occurrence_count = 2
        expect(page).to have_content("RuntimeError")
        # The occurrence count badge should show 2
        expect(page).to have_content("2")
      end
    end

    context "when ExceptionFilter blocks ignored exceptions" do
      it "does not show ignored exceptions on the dashboard" do
        RailsErrorDashboard.configure { |c| c.ignored_exceptions = [ "ArgumentError" ] }

        # This should be filtered out by ExceptionFilter
        ignored = ArgumentError.new("bad arg")
        ignored.set_backtrace([ "#{Rails.root}/app/controllers/test_controller.rb:1" ])
        RailsErrorDashboard::Commands::LogError.call(ignored, {})

        # This should go through
        allowed = TypeError.new("wrong type")
        allowed.set_backtrace([ "#{Rails.root}/app/controllers/test_controller.rb:2" ])
        RailsErrorDashboard::Commands::LogError.call(allowed, {})

        visit_dashboard("/errors")
        wait_for_page_load

        expect(page).to have_content("TypeError")
        expect(page).not_to have_content("ArgumentError")
      end
    end

    context "when LogError creates error with proper hash" do
      it "shows the error on the detail page with correct attributes" do
        error = NameError.new("undefined local variable 'x'")
        error.set_backtrace([ "#{Rails.root}/app/controllers/widgets_controller.rb:10:in `show'" ])

        result = RailsErrorDashboard::Commands::LogError.call(error, {
          controller_name: "widgets", action_name: "show"
        })

        visit_error(result)
        wait_for_page_load

        expect(page).to have_content("NameError")
        expect(page).to have_content("undefined local variable 'x'")
        expect(page).to have_content("widgets_controller.rb")
      end
    end
  end

  describe "Notification payload builders (Phase 7)" do
    after { RailsErrorDashboard.reset_configuration! }

    context "when error is created and notifications are dispatched" do
      it "logs error with correct details even when Slack notifications enabled" do
        RailsErrorDashboard.configure do |c|
          c.enable_slack_notifications = true
          c.slack_webhook_url = "https://hooks.slack.com/test-fake"
        end

        error = RuntimeError.new("Payload builder integration test")
        error.set_backtrace([ "#{Rails.root}/app/controllers/payments_controller.rb:15:in `charge'" ])

        # LogError delegates to ErrorNotificationDispatcher which enqueues SlackErrorNotificationJob
        # which uses SlackPayloadBuilder — the full chain should not raise
        result = RailsErrorDashboard::Commands::LogError.call(error, {
          controller_name: "payments", action_name: "charge"
        })

        expect(result).to be_present
        expect(result.error_type).to eq("RuntimeError")

        visit_error(result)
        wait_for_page_load

        expect(page).to have_content("RuntimeError")
        expect(page).to have_content("Payload builder integration test")
        expect(page).to have_content("payments_controller.rb")
      end
    end

    context "when payload builders produce valid data" do
      let!(:payload_error) do
        create(:error_log,
          application: application,
          error_type: "WebhookTestError",
          message: "Testing webhook payload structure",
          controller_name: "api",
          action_name: "submit",
          platform: "API",
          occurrence_count: 5,
          backtrace: "app/controllers/api_controller.rb:20:in `submit'")
      end

      it "renders error with all fields that payload builders extract" do
        visit_error(payload_error)
        wait_for_page_load

        # These are the same fields that SlackPayloadBuilder, DiscordPayloadBuilder,
        # WebhookPayloadBuilder, and PagerdutyPayloadBuilder read from error_log
        expect(page).to have_content("WebhookTestError")
        expect(page).to have_content("Testing webhook payload structure")
        expect(page).to have_content("API")
        expect(page).to have_content("5x")
      end
    end
  end

  describe "Overview page with DashboardStats integration" do
    context "when spike detection runs through BaselineCalculator" do
      before do
        # Create enough errors today to trigger spike detection
        10.times do |i|
          create(:error_log,
            application: application,
            error_type: "SpikeError",
            message: "Error spike today",
            occurred_at: i.minutes.ago)
        end
      end

      it "loads overview page with stats" do
        visit_dashboard
        wait_for_page_load
        expect(page).to have_content("Dashboard")
        expect(page).to have_content("ERROR RATE")
        expect(page).to have_content("UNRESOLVED ERRORS")
      end
    end
  end

  describe "Cascade pattern commands (Phase 8)" do
    let!(:parent_error) do
      create(:error_log,
        application: application,
        error_type: "DatabaseConnectionError",
        message: "Connection pool exhausted",
        occurred_at: 30.minutes.ago)
    end

    let!(:child_error) do
      create(:error_log,
        application: application,
        error_type: "NoMethodError",
        message: "undefined method for nil:NilClass",
        occurred_at: 29.minutes.ago)
    end

    context "when cascade patterns exist and are displayed on error show page" do
      before do
        RailsErrorDashboard.configuration.enable_error_cascades = true

        # Create cascade pattern with high frequency
        pattern = RailsErrorDashboard::CascadePattern.create!(
          parent_error: parent_error,
          child_error: child_error,
          frequency: 7,
          avg_delay_seconds: 10.0,
          last_detected_at: Time.current
        )

        # Use IncrementCascadeDetection command (via model delegation) → frequency becomes 8
        pattern.increment_detection!(14.0)

        # Create parent occurrences for probability calculation (total = 10)
        10.times { |i| create(:error_occurrence, error_log: parent_error, occurred_at: (i + 1).minutes.ago) }

        # Use CalculateCascadeProbability command (via model delegation)
        # probability = 8 / 10 = 0.8 (above 0.5 threshold)
        pattern.calculate_probability!
      end

      after do
        RailsErrorDashboard.configuration.enable_error_cascades = false
      end

      it "displays cascade pattern data computed by commands on the error detail page" do
        visit_error(child_error)
        wait_for_page_load

        # The cascade section should show parent→child relationship
        expect(page).to have_content("Error Cascades")
        expect(page).to have_content("Triggered By")
        expect(page).to have_content("DatabaseConnectionError")

        # Verify frequency: started at 7, incremented once = 8
        expect(page).to have_content("8x")

        # Verify avg_delay: ((10.0 * 7) + 14.0) / 8 = 84/8 = 10.5
        expect(page).to have_content("10.5s")
      end
    end

    context "when IncrementCascadeDetection and CalculateCascadeProbability commands work correctly" do
      it "increments frequency and computes probability through model delegation" do
        pattern = RailsErrorDashboard::CascadePattern.create!(
          parent_error: parent_error,
          child_error: child_error,
          frequency: 5,
          avg_delay_seconds: 20.0,
          last_detected_at: 1.hour.ago
        )

        # Increment via model delegation (calls Commands::IncrementCascadeDetection)
        pattern.increment_detection!(32.0)
        expect(pattern.frequency).to eq(6)
        # ((20.0 * 5) + 32.0) / 6 = 132/6 = 22.0
        expect(pattern.avg_delay_seconds).to eq(22.0)

        # Create occurrences and calculate probability (calls Commands::CalculateCascadeProbability)
        12.times { |i| create(:error_occurrence, error_log: parent_error, occurred_at: (i + 1).minutes.ago) }
        pattern.calculate_probability!

        total_occ = parent_error.error_occurrences.count
        expected_prob = (6.0 / total_occ).round(3)
        expect(pattern.cascade_probability).to eq(expected_prob)

        # Verify the data appears on the show page
        RailsErrorDashboard.configuration.enable_error_cascades = true
        visit_error(child_error)
        wait_for_page_load

        expect(page).to have_content("Error Cascades")
        expect(page).to have_content("6x")
      ensure
        RailsErrorDashboard.configuration.enable_error_cascades = false
      end
    end
  end
end
