# frozen_string_literal: true

require "rails_helper"

# Timestamps in the discussion card: the audit trail's own comments, and the
# comments fetched from a linked issue tracker.
RSpec.describe "Discussion timestamps", type: :request do
  let!(:application) { create(:application) }
  let(:error) { create(:error_log, application: application) }
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    forgery = ActionController::Base.allow_forgery_protection
    tracking = config.enable_issue_tracking
    config.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
    Rails.cache.clear
    example.run
  ensure
    config.authenticate_with = nil
    config.enable_issue_tracking = tracking
    ActionController::Base.allow_forgery_protection = forgery
    Rails.cache.clear
  end

  describe "audit trail comments" do
    before do
      error.comments.create!(author_name: "gandalf", body: "looking into it", created_at: Time.utc(2026, 3, 9, 14, 5))
    end

    it "renders the time through local_time, in the viewer's format" do
      get "/error_dashboard/errors/#{error.id}"

      stamp = Nokogiri::HTML(response.body).at_css("#section-discussion .local-time")
      expect(stamp).to be_present
      expect(stamp["data-utc"]).to eq("2026-03-09T14:05:00Z")
      expect(stamp["data-format"]).to eq(I18n.t("red.time.formats.datetime"))
      # The hardcoded US pattern: "Mar 09, 2026 at 02:05 PM".
      expect(response.body).not_to include("2026 at 02:05 PM")
    end

    it "uses the locale's own date ordering" do
      post "/error_dashboard/locale", params: { locale: "de" }

      get "/error_dashboard/errors/#{error.id}"

      stamp = Nokogiri::HTML(response.body).at_css("#section-discussion .local-time")
      expect(stamp["data-format"]).to eq("%d. %b %Y %H:%M")
    end
  end

  # created_at comes from a forge's API. Time.parse raised on anything that was
  # not a date, and one odd comment took the whole error page down.
  describe "issue tracker comments" do
    before do
      config.enable_issue_tracking = true
      error.update_columns(external_issue_url: "https://github.com/a/b/issues/1",
                           external_issue_number: 1, external_issue_provider: "github")
    end

    def stub_comments(*created_ats)
      comments = created_ats.each_with_index.map do |created_at, i|
        { author: "user#{i}", body: "comment body #{i}", created_at: created_at, avatar_url: nil }
      end
      client = instance_double(RailsErrorDashboard::Services::GitHubIssueClient)
      allow(client).to receive(:fetch_issue).and_return({ success: false })
      allow(client).to receive(:fetch_comments).and_return({ success: true, comments: comments })
      allow(RailsErrorDashboard::Services::IssueTrackerClient).to receive(:for_error).and_return(client)
    end

    [ "", "not a date", nil, "2026-99-99T99:99:99Z", 12_345, { "a" => 1 } ].each do |value|
      it "renders the page with an empty time for created_at #{value.inspect}" do
        stub_comments(value)

        get "/error_dashboard/errors/#{error.id}"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("comment body 0")
        expect(response.body).not_to include("Something went wrong")
        expect(Nokogiri::HTML(response.body).css("#section-discussion .local-time")).to be_empty
      end
    end

    it "still renders a valid timestamp, and one bad comment does not hide the others" do
      stub_comments("2026-01-02T03:04:05Z", "garbage")

      get "/error_dashboard/errors/#{error.id}"

      stamps = Nokogiri::HTML(response.body).css("#section-discussion .local-time")
      expect(stamps.map { |s| s["data-utc"] }).to eq([ "2026-01-02T03:04:05Z" ])
      expect(response.body).to include("comment body 1")
    end
  end
end
