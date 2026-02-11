# frozen_string_literal: true

module ModalHelpers
  # Wait for a Bootstrap modal to fully animate open, then yield within its scope.
  # Bootstrap adds the "show" class after the animation completes.
  def within_modal(modal_id)
    modal = find("##{modal_id}.show", visible: true, wait: 5)
    within(modal) { yield }
  end

  # Open the Assign modal, fill in the assignee, and submit
  def assign_error_to(name)
    find("[data-bs-target='#assignModal']").click
    within_modal("assignModal") do
      fill_in "assigned_to", with: name
      find("input[type='submit'][value='Assign']").click
    end
  end

  # Click the unassign button.
  # Note: data-turbo-confirm only fires when Turbo JS is loaded.
  # In the test dummy app without Turbo, the form submits directly.
  # In production with Turbo, the browser confirm dialog would appear first.
  def unassign_error
    find("form[action*='/unassign'] button[type='submit']").click
  end

  # Open the Priority modal, select a priority level, and submit
  def set_priority_to(label)
    find("[data-bs-target='#priorityModal']").click
    within_modal("priorityModal") do
      select label, from: "priority_level"
      find("input[type='submit'][value='Update Priority']").click
    end
  end

  # Open the Snooze modal, select duration, optionally fill reason, and submit
  def snooze_error_for(duration_label, reason: nil)
    find("[data-bs-target='#snoozeModal']").click
    within_modal("snoozeModal") do
      select duration_label, from: "hours"
      fill_in "reason", with: reason if reason
      find("input[type='submit'][value='Snooze']").click
    end
  end

  # Click the Unsnooze button (no modal, direct button_to form)
  def unsnooze_error
    find("form[action*='/unsnooze'] button[type='submit']").click
  end

  # Open the Resolve modal, fill in details, and submit
  def resolve_error(name:, comment: nil, reference: nil)
    find("[data-bs-target='#resolveModal']").click
    within_modal("resolveModal") do
      fill_in "resolved_by_name", with: name
      fill_in "resolution_reference", with: reference if reference
      fill_in "resolution_comment", with: comment if comment
      find("input[type='submit'][value='Mark as Resolved']").click
    end
  end

  # Fill in and submit the inline comment form
  def add_comment(author:, body:)
    within("form[action*='/add_comment']") do
      fill_in "author_name", with: author
      fill_in "body", with: body
      find("input[type='submit'][value='Post Comment']").click
    end
  end
end

RSpec.configure do |config|
  config.include ModalHelpers, type: :system
end
