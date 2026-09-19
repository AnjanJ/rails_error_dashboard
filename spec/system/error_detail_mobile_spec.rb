# frozen_string_literal: true

require "rails_helper"

# The error DETAIL page at phone width.
#
# p7_layout_qa_spec visits /errors, /overview, /errors/analytics and /settings,
# but never an individual error, so the page an on-call engineer actually opens
# at 3am was never rendered at any width. It was badly broken: the hero's
# action row carried `flex-shrink: 0` against a plain `flex: 1` title column,
# so at 390px up to five buttons kept their full width and the title absorbed
# the whole squeeze -- "NoMethodError" wrapped to roughly one character per
# line, producing a very tall header before the backtrace.
RSpec.describe "error detail at phone width", type: :system do
  let!(:application) { create(:application) }

  PHONE = [ 390, 844 ].freeze
  RESTORE = [ 1400, 900 ].freeze

  let!(:error) do
    create(
      :error_log,
      application: application,
      error_type: "NoMethodError",
      message: "undefined method 'total' for nil in checkout confirmation",
      request_url: "https://shop.example.test/checkout/confirm"
    )
  end

  before do
    page.driver.resize_window(*PHONE)
  end

  after do
    # Cuprite does not restore the viewport between examples -- the window
    # belongs to the browser, not the session -- so a resize would otherwise
    # hand the next spec a mobile layout.
    page.driver.resize_window(*RESTORE)
  end

  it "does not scroll sideways" do
    visit_error(error)

    measured = page.evaluate_script(<<~JS)
      ({ scroll: document.documentElement.scrollWidth,
         client: document.documentElement.clientWidth })
    JS

    expect(measured["scroll"]).to be <= measured["client"],
      "the detail page scrolls sideways at #{PHONE.first}px " \
      "(#{measured['scroll']}px of content in a #{measured['client']}px viewport)"
  end

  it "keeps the error type readable instead of one character per line" do
    visit_error(error)

    # The hero title's box must be wide enough to hold real words. A column
    # squeezed to a few characters is the defect; the exact width is not the
    # point, so this asserts the floor the 260px flex-basis guarantees.
    width = page.evaluate_script(
      "document.querySelector('.red-error-hero-text').getBoundingClientRect().width"
    )

    expect(width).to be > 200,
      "the hero text column collapsed to #{width.round}px — the action row is " \
      "squeezing the title again"
  end

  it "wraps the action row onto its own line rather than crushing the title" do
    visit_error(error)

    stacked = page.evaluate_script(<<~JS)
      (() => {
        const text = document.querySelector('.red-error-hero-text').getBoundingClientRect();
        const actions = document.querySelector('.red-error-hero-actions').getBoundingClientRect();
        return actions.top >= text.bottom - 1;
      })()
    JS

    expect(stacked).to be(true),
      "the actions are still beside the title at #{PHONE.first}px"
  end

  it "is unchanged on the desktop layout" do
    page.driver.resize_window(*RESTORE)
    visit_error(error)

    side_by_side = page.evaluate_script(<<~JS)
      (() => {
        const text = document.querySelector('.red-error-hero-text').getBoundingClientRect();
        const actions = document.querySelector('.red-error-hero-actions').getBoundingClientRect();
        return actions.top < text.bottom;
      })()
    JS

    expect(side_by_side).to be(true),
      "the hero stacked on desktop — the breakpoint is too wide"
  end
end
