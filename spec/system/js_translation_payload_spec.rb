# frozen_string_literal: true

require "rails_helper"

# The request specs pin what the server sends. These pin what the browser does
# with it — that redT actually resolves, that it survives a Turbo navigation,
# and that the payload block raises nothing on load. Those are the P3-T1 QA
# criteria a request spec cannot reach.
RSpec.describe "JS translation payload in the browser", type: :system do
  let!(:application) { create(:application) }

  it "exposes RED_I18N and redT to page scripts" do
    visit_dashboard("/errors")
    wait_for_page_load

    expect(page.evaluate_script("typeof window.RED_I18N")).to eq("object")
    expect(page.evaluate_script("typeof window.redT")).to eq("function")
  end

  it "resolves nested keys and interpolates" do
    visit_dashboard("/errors")
    wait_for_page_load

    expect(page.evaluate_script("window.redT('js.meridian.pm')")).to eq("PM")
    expect(page.evaluate_script("window.redT('formats.full')")).to eq("%B %d, %Y %I:%M:%S %p")

    # Arrays are read off RED_I18N directly. redT resolves strings only — an
    # array node is a miss, so it returns the key (see the miss example below).
    expect(page.evaluate_script("window.RED_I18N.js.months[0]")).to eq("January")
  end

  # REQ-5. A missing key must degrade to the key itself. Returning undefined
  # would render the string "undefined" into the UI; throwing would take out
  # whatever handler called it.
  it "returns the key itself for a miss, and does not throw" do
    visit_dashboard("/errors")
    wait_for_page_load

    expect(page.evaluate_script("window.redT('nope.not.here')")).to eq("nope.not.here")
    expect(page.evaluate_script("window.redT('js.meridian')")).to eq("js.meridian")
    expect(page.evaluate_script("window.redT('js.months')")).to eq("js.months")
    expect(page.evaluate_script("(function(){ try { window.redT(null); return 'no-throw'; } catch (e) { return 'threw'; } })()"))
      .to eq("no-throw")
  end

  # P3-T3 added plural support: the selected-count is only known once a box is
  # ticked, so the browser picks the form. A ternary on "s" at the call site is
  # the anti-pattern this exists to prevent.
  it "selects a plural form when given a count" do
    visit_dashboard("/errors")
    wait_for_page_load

    expect(page.evaluate_script("window.redT('js.selected', { count: 1 })")).to eq("1 selected")
    expect(page.evaluate_script("window.redT('js.selected', { count: 4 })")).to eq("4 selected")
  end

  it "falls back to :other when a locale ships no :one form" do
    visit_dashboard("/errors")
    wait_for_page_load

    page.execute_script("window.__saved = window.RED_I18N; window.RED_I18N = { js: { pick: { other: '%{count} x' } } };")

    expect(page.evaluate_script("window.redT('js.pick', { count: 1 })")).to eq("1 x")
  ensure
    page.execute_script("window.RED_I18N = window.__saved;")
  end

  # A branch without a count is still a miss — redT returns strings only.
  it "returns the key for a plural branch when no count is given" do
    visit_dashboard("/errors")
    wait_for_page_load

    expect(page.evaluate_script("window.redT('js.selected')")).to eq("js.selected")
  end

  # The payload is assigned at parse time in <head>, not on a load event, so it
  # must be defined by the time later scripts and Turbo-rendered pages run.
  it "is still defined after navigating between dashboard pages" do
    visit_dashboard("/errors")
    wait_for_page_load

    visit_dashboard("/errors/analytics")
    wait_for_page_load

    expect(page.evaluate_script("typeof window.redT")).to eq("function")
    expect(page.evaluate_script("window.RED_I18N.js.days[0]")).to eq("Sunday")
  end

  # A syntax error in the payload block would leave redT undefined and every
  # later caller broken. Evaluating both names is the direct check; the
  # regex-over-console-logs approach is not portable to Cuprite.
  it "loads the payload block without breaking the page" do
    visit_dashboard("/errors")
    wait_for_page_load

    expect(page.evaluate_script("window.RED_I18N !== undefined && typeof window.redT === 'function'"))
      .to be(true)

    # The block is an IIFE; a throw inside it would abort before redT is
    # assigned. Reaching a working redT proves it ran to completion.
    expect(page.evaluate_script("window.redT('js.meridian.am')")).to eq("AM")
  end
end
