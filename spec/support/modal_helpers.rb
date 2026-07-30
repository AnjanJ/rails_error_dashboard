# frozen_string_literal: true

module ModalHelpers
  # Wait for a Bootstrap modal to fully animate open, then yield within its scope.
  # Bootstrap adds the "show" class after the animation completes.
  def within_modal(modal_id)
    modal = find("##{modal_id}.show", visible: true, wait: 10)
    # `.show` is added when the transition STARTS, not when it ends. Submitting
    # mid-animation lets the backdrop swallow the click, so settle first.
    wait_for_modal_animation(modal_id)
    within(modal) { yield }
  end

  # Open a modal by clicking its trigger, retrying once if the modal does not
  # appear.
  #
  # Two races make a single blind click unreliable:
  #   1. Bootstrap's JS is CDN-loaded, so a click before it executes is a no-op
  #      (`data-bs-toggle` isn't bound yet).
  #   2. A click can land while the page is still settling and be swallowed.
  #
  # Neither raises anything useful — they surface as `Unable to find css
  # "#someModal.show"` several lines later. Waiting for Bootstrap and retrying
  # the click removes both.
  def open_modal(modal_id, trigger_selector = nil)
    trigger_selector ||= "[data-bs-target='##{modal_id}']"
    wait_for_bootstrap

    first(trigger_selector).click
    return if has_css?("##{modal_id}.show", visible: true, wait: 5)

    # Modal never opened — the click was almost certainly lost. Try once more.
    first(trigger_selector).click
  end

  # Bootstrap toggles `.show` at the start of the fade transition. Wait for the
  # element to stop moving so clicks inside it land on the intended target.
  def wait_for_modal_animation(modal_id, timeout: 5)
    deadline = Time.now + timeout
    last = nil
    loop do
      current = page.evaluate_script(
        "(function(){var m=document.getElementById('#{modal_id}');" \
        "if(!m)return null;var r=m.getBoundingClientRect();" \
        "return [r.top, r.left, window.getComputedStyle(m).opacity].join(',');})()"
      )
      return true if current && current == last
      break if Time.now > deadline

      last = current
      sleep 0.05
    end
    false
  rescue StandardError
    false
  end

  # Open the Assign modal, fill in the assignee, and submit
  # Use open_modal since the redesign has assign buttons in both hero card and sidebar
  def assign_error_to(name)
    open_modal("assignModal")
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
    open_modal("priorityModal")
    within_modal("priorityModal") do
      select label, from: "priority_level"
      find("input[type='submit'][value='Update Priority']").click
    end
  end

  # Open the Snooze modal, select duration, optionally fill reason, and submit
  def snooze_error_for(duration_label, reason: nil)
    open_modal("snoozeModal")
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

  # Open the Mute modal, optionally fill in name and reason, and submit
  def mute_error(muted_by: nil, reason: nil)
    open_modal("muteModal")
    within_modal("muteModal") do
      fill_in "muted_by", with: muted_by if muted_by
      fill_in "reason", with: reason if reason
      find("input[type='submit'][value='Mute Notifications']").click
    end
  end

  # Click the Unmute button (no modal, direct button_to form)
  def unmute_error
    find("form[action*='/unmute'] button[type='submit']").click
  end

  # Open the Resolve modal, fill in details, and submit
  def resolve_error(name:, comment: nil, reference: nil)
    open_modal("resolveModal")
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
