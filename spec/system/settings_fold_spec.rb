# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-0/REQ-8: an open group's body has no inline display, and the
# toggle read an empty display as "hidden", so the first click opened the
# already open group and only the second folded it.
RSpec.describe "Settings group fold", type: :system do
  it "folds an open group on the first click, and opens it on the second" do
    visit_dashboard("/settings")
    wait_for_page_load

    header = first("button[data-red-action='toggle-next']")
    body = header.find(:xpath, "following-sibling::*[1]")
    expect(body).to be_visible

    header.click
    expect(body).not_to be_visible

    header.click
    expect(body).to be_visible
  end
end
