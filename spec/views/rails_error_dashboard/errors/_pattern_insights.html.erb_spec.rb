# frozen_string_literal: true

require "rails_helper"

RSpec.describe "rails_error_dashboard/errors/_pattern_insights", type: :view do
  before(:all) do
    ActionView::TestCase::TestController.helper(RailsErrorDashboard::ApplicationHelper)
    ActionView::TestCase::TestController.helper(RailsErrorDashboard::I18nHelper)
  end

  let(:error) { create(:error_log) }
  let(:pattern) do
    { pattern_type: :business_hours, peak_hours: [ 13 ], hourly_distribution: { 13 => 5 }, weekday_distribution: { 3 => 5 },
      pattern_strength: 0.8, total_errors: 5, analysis_days: 30 }
  end

  before do
    allow(RailsErrorDashboard.configuration).to receive(:enable_occurrence_patterns).and_return(true)
    allow(error).to receive(:occurrence_pattern).and_return(pattern)
    allow(error).to receive(:error_bursts).and_return([])
    assign(:error, error)
  end

  around { |example| Time.use_zone("Asia/Kolkata") { example.run } }

  def heatmap_and_peak_hours
    render partial: "rails_error_dashboard/errors/pattern_insights"
    Nokogiri::HTML(rendered)
  end

  it "names the zone next to the heatmap (small-fixes-0-18/REQ-5)" do
    page = heatmap_and_peak_hours

    expect(page.at_css(".heatmap-cell-wrapper").parent.parent.text).to include("Asia/Kolkata")
  end

  it "names the zone next to the peak hours (small-fixes-0-18/REQ-5)" do
    page = heatmap_and_peak_hours

    expect(page.at_css(".alert.alert-info").text).to include("Asia/Kolkata")
  end
end
