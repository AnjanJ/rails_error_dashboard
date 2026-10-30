# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::ApplicationHelper, "#platform_badge", type: :helper do
  { "iOS" => %w[ios IOS iOS], "Android" => %w[android ANDROID Android], "Web" => %w[web WEB Web] }.each do |label, spellings|
    spellings.each do |platform|
      it "gives #{platform} the #{label} badge (small-fixes-0-18/REQ-3)" do
        badge = helper.platform_badge(platform)

        expect(badge).to include("badge-#{label.downcase}", "</i> #{label}</span>")
        expect(badge).not_to include("badge-api")
      end
    end
  end

  %w[API Mobile].each do |platform|
    it "keeps #{platform}'s own text on the grey badge (small-fixes-0-18/REQ-3)" do
      expect(helper.platform_badge(platform)).to eq(%(<span class="badge badge-api"><i class="bi bi-server"></i> #{platform}</span>))
    end
  end

  it "shows API when there's no platform, as the error row did (small-fixes-0-18/REQ-3)" do
    expect(helper.platform_badge(nil)).to include("badge-api", "> API<")
  end

  it "writes what the views wrote, byte for byte (small-fixes-0-18/REQ-3)" do
    expect(helper.platform_badge("ios")).to eq(%(<span class="badge badge-ios"><i class="bi bi-apple"></i> iOS</span>))
  end

  it "takes the timeline's extra class (small-fixes-0-18/REQ-3)" do
    expect(helper.platform_badge("web", css: "ms-2")).to eq(%(<span class="badge badge-web ms-2"><i class="bi bi-globe"></i> Web</span>))
  end

  it "escapes a platform it doesn't know, because a client sets it (small-fixes-0-18/REQ-3)" do
    expect(helper.platform_badge("<script>")).to include("&lt;script&gt;").and(satisfy { |html| !html.include?("<script>") })
  end

  %w[_error_row _timeline _similar_errors _sidebar_metadata].each do |partial|
    it "is what #{partial} renders with, not a copy of the branch (small-fixes-0-18/REQ-3)" do
      source = RailsErrorDashboard::Engine.root.join("app/views/rails_error_dashboard/errors/#{partial}.html.erb").read

      expect(source).to include("platform_badge(")
      expect(source).not_to match(/platform == '(iOS|Android|Web)'/)
    end
  end
end
