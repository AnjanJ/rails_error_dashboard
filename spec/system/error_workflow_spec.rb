# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Error Workflow", type: :system do
  let!(:application) { create(:application) }
  let!(:error_log) do
    create(:error_log,
      application: application,
      error_type: "NoMethodError",
      message: "undefined method 'foo' for nil:NilClass",
      status: "new",
      priority_level: 0,
      resolved: false,
      resolved_at: nil,
      assigned_to: nil,
      assigned_at: nil,
      snoozed_until: nil)
  end

  describe "full error lifecycle" do
    it "performs all workflow actions on an error" do
      # Step 1: Visit error detail page
      visit_error(error_log)
      wait_for_page_load
      expect(page).to have_content("NoMethodError")
      expect(page).to have_content("undefined method 'foo' for nil:NilClass")

      # Step 2: Assign to "gandalf"
      assign_error_to("gandalf")
      wait_for_page_load
      expect(page).to have_content("gandalf")
      # Unassign button should now be visible
      expect(page).to have_css("form[action*='/unassign']")

      # Step 3: Unassign
      unassign_error
      wait_for_page_load
      # Assign button should be back, unassign form gone
      expect(page).to have_css("[data-bs-target='#assignModal']")
      expect(page).not_to have_css("form[action*='/unassign']")

      # Step 4: Set priority to Critical
      set_priority_to("Critical (P0)")
      wait_for_page_load
      expect(page).to have_content("Critical (P0)")

      # Step 5: Snooze for 1 hour with reason
      snooze_error_for("1 hour", reason: "Investigating root cause")
      wait_for_page_load
      expect(page).to have_content("Snoozed")
      expect(page).to have_content("Investigating root cause")

      # Step 6: Unsnooze
      unsnooze_error
      wait_for_page_load
      # The snooze alert indicator should be gone (but the snooze comment in Discussion remains)
      expect(page).not_to have_css(".alert-warning", text: "Snoozed")
      expect(page).to have_css("[data-bs-target='#snoozeModal']")

      # Step 7: Assign again → status auto-changes to "In Progress"
      assign_error_to("gandalf")
      wait_for_page_load
      expect(page).to have_content("In Progress")

      # Step 8: Resolve with comment
      resolve_error(
        name: "gandalf",
        comment: "Fixed the nil reference bug",
        reference: "PR-42"
      )
      wait_for_page_load
      expect(page).to have_content("Resolved")
      expect(page).to have_content("gandalf")

      # Step 9: Add comment
      add_comment(author: "gandalf", body: "Verified fix in staging")
      wait_for_page_load
      expect(page).to have_content("Verified fix in staging")

      # Step 10: Invalid status transition via fetch()
      # Error is resolved — "in_progress" is not a valid transition from "resolved"
      page.execute_script(<<~JS)
        fetch(window.location.pathname.replace(/\\/\\d+$/, '/#{error_log.id}/update_status'), {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
          },
          body: 'status=in_progress'
        })
      JS
      sleep 1
      visit_error(error_log)
      wait_for_page_load
      # Status should remain "Resolved" (invalid transition rejected)
      expect(page).to have_content("Resolved")
    end
  end

  describe "dashboard pages load" do
    it "loads the overview page" do
      visit_dashboard
      wait_for_page_load
      expect(page).to have_content("Dashboard")
    end

    it "loads the errors index" do
      visit_dashboard("/errors")
      wait_for_page_load
      expect(page).to have_content("NoMethodError")
    end

    it "loads the analytics page" do
      visit_dashboard("/errors/analytics")
      wait_for_page_load
      expect(page).to have_content("Analytics")
    end

    it "loads the settings page" do
      visit_dashboard("/settings")
      wait_for_page_load
      expect(page).to have_content("Settings")
    end
  end

  describe "error list navigation" do
    it "navigates from error list to error detail" do
      visit_dashboard("/errors")
      wait_for_page_load
      expect(page).to have_content("NoMethodError")
      # Click the error row (table rows use onclick to navigate)
      find("td", text: "NoMethodError").click
      wait_for_page_load
      expect(page).to have_content("undefined method 'foo' for nil:NilClass")
    end
  end
end
