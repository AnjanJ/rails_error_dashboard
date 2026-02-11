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
end
