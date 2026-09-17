# frozen_string_literal: true

require "rails_helper"

# The "/" shortcut focused the top-bar search box, and Enter then did nothing:
# the input had no form and no name. This drives it the way a user does.
RSpec.describe "Global search", type: :system do
  let!(:application) { create(:application) }
  let!(:hit) { create(:error_log, application: application, error_type: "NeedleError", message: "needle in the haystack") }
  let!(:miss) { create(:error_log, application: application, error_type: "OtherError", message: "nothing to see here") }

  it "searches from any page with the / shortcut, typing, and Enter" do
    visit_dashboard("/errors/analytics")
    wait_for_page_load

    find("body").send_keys("/")
    expect(page.evaluate_script("document.activeElement.id")).to eq("globalSearch")

    find("#globalSearch").send_keys("needle", :enter)

    expect(page).to have_current_path(%r{/errors\?(.*&)?search=needle})
    expect(page).to have_content("needle in the haystack")
    expect(page).to have_no_content("nothing to see here")
    expect(find("#globalSearch").value).to eq("needle")
  end
end
