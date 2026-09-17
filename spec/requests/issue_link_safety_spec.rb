# frozen_string_literal: true

require "rails_helper"

# Every URL on the error page that comes from a stored column or from a
# third-party issue tracker must be plain http(s) before it becomes an href, an
# img src or a window.open target. LinkExistingIssue validates at write time;
# this covers render time, which also protects rows stored before that check
# existed and values returned by a forge API.
RSpec.describe "Issue link safety on the error page", type: :request do
  let!(:application) { create(:application) }
  let(:error) { create(:error_log, application: application) }
  let(:config) { RailsErrorDashboard.configuration }
  let(:unsafe_note) { I18n.t("red.errors.issue_section.unsafe_link") }

  before do
    config.authenticate_with = -> { true }
    @was_tracking = config.enable_issue_tracking
    config.enable_issue_tracking = true
    ActionController::Base.allow_forgery_protection = false
    Rails.cache.clear
  end

  after do
    config.authenticate_with = nil
    config.enable_issue_tracking = @was_tracking
    ActionController::Base.allow_forgery_protection = true
    Rails.cache.clear
  end

  # update_columns skips the command, simulating a row written before the
  # write-time check existed.
  def store_link(url, number: 1, provider: "github")
    error.update_columns(external_issue_url: url, external_issue_number: number, external_issue_provider: provider)
  end

  def stub_tracker(issue: nil, comments: [])
    client = instance_double(RailsErrorDashboard::Services::GitHubIssueClient)
    allow(client).to receive(:fetch_issue).and_return(issue ? issue.merge(success: true) : { success: false })
    allow(client).to receive(:fetch_comments).and_return({ success: true, comments: comments })
    allow(RailsErrorDashboard::Services::IssueTrackerClient).to receive(:for_error).and_return(client)
  end

  describe "a stored external_issue_url with a javascript: scheme" do
    before do
      store_link("javascript:window.__PWN=1")
      get "/error_dashboard/errors/#{error.id}"
    end

    it "renders the page" do
      expect(response).to have_http_status(:ok)
    end

    it "is never emitted as an href" do
      expect(response.body).not_to match(/href\s*=\s*["']?\s*javascript:/i)
    end

    it "is shown as inert escaped text with an explanation" do
      expect(response.body).to include(unsafe_note)
      expect(response.body).to include("javascript:window.__PWN=1")
    end
  end

  it "escapes an unsafe stored URL that also tries to break out of the markup" do
    store_link(%(javascript:x"><script>window.__PWN=1</script>))

    get "/error_dashboard/errors/#{error.id}"

    expect(response.body).not_to include("<script>window.__PWN=1</script>")
    expect(response.body).not_to match(/href\s*=\s*["']?\s*javascript:/i)
  end

  it "still renders a valid https URL as a link in all three places" do
    store_link("https://github.com/a/b/issues/1")

    get "/error_dashboard/errors/#{error.id}"

    expect(response.body.scan('href="https://github.com/a/b/issues/1"').size).to eq(3)
    expect(response.body).not_to include(unsafe_note)
  end

  describe "third-party avatar URLs" do
    before { store_link("https://github.com/a/b/issues/1") }

    it "drops an assignee avatar that is not http(s) and keeps the login" do
      stub_tracker(issue: { state: "open", labels: [],
                            assignees: [ { login: "mallory", avatar_url: "javascript:window.__PWN=1" } ] })

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("mallory")
      expect(response.body).not_to match(/src\s*=\s*["']?\s*javascript:/i)
    end

    it "drops a comment avatar that is not http(s) and keeps the comment" do
      stub_tracker(comments: [ { author: "mallory", body: "hello there", created_at: "2026-01-01T00:00:00Z",
                                 avatar_url: "data:image/svg+xml,<svg onload=alert(1)>" } ])

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("hello there")
      expect(response.body).not_to match(/src\s*=\s*["']?\s*data:/i)
    end

    it "still renders https avatars" do
      stub_tracker(issue: { state: "open", labels: [],
                            assignees: [ { login: "alice", avatar_url: "https://avatars.test/alice.png" } ] },
                   comments: [ { author: "bob", body: "hi", created_at: "2026-01-01T00:00:00Z",
                                 avatar_url: "https://avatars.test/bob.png" } ])

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include('src="https://avatars.test/alice.png"')
      expect(response.body).to include('src="https://avatars.test/bob.png"')
    end
  end

  # A label colour goes into a style attribute. ERB escaping keeps it inside
  # the attribute but does nothing about the CSS itself.
  describe "third-party label colours" do
    before { store_link("https://github.com/a/b/issues/1") }

    it "does not let a label colour inject CSS" do
      stub_tracker(issue: { state: "open", assignees: [],
                            labels: [ { name: "evil", color: "fff;position:fixed;inset:0;background:url(//evil.test/x)" } ] })

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("evil")
      expect(response.body).not_to include("position:fixed")
      expect(response.body).not_to include("evil.test")
      expect(response.body).to include("background-color: #6c757d")
    end

    it "still renders a valid label colour with a readable text colour" do
      stub_tracker(issue: { state: "open", assignees: [],
                            labels: [ { name: "bug", color: "d73a4a" }, { name: "pale", color: "fef2c0" } ] })

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("background-color: #d73a4a; color: #fff")
      expect(response.body).to include("background-color: #fef2c0; color: #000")
    end

    it "renders the page when a label colour is not a string" do
      stub_tracker(issue: { state: "open", assignees: [], labels: [ { name: "odd", color: 123 }, { name: "none", color: nil } ] })

      get "/error_dashboard/errors/#{error.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body.scan("background-color: #6c757d; color: #fff").size).to eq(2)
    end
  end

  # Static guard: a stored or third-party URL may reach an href/src/window.open
  # only through a local assigned from safe_external_url, never directly.
  it "has no view that puts a raw stored or third-party URL into a link target" do
    engine_root = RailsErrorDashboard::Engine.root
    # Matched against the whole file: the sidebar's link_to spans two lines.
    sink = /(?:href|src)\s*=\s*["']?<%=[^%]*(?:external_issue_url|avatar_url|html_url|flash\[)|window\.open\([^)]*flash\[|link_to\b[^%]*\.external_issue_url/m

    offenders = Dir[engine_root.join("app/views/**/*.erb")].flat_map do |file|
      source = File.read(file)
      source.to_enum(:scan, sink).map do
        line = source[0, Regexp.last_match.begin(0)].count("\n") + 1
        "#{Pathname(file).relative_path_from(engine_root)}:#{line}"
      end
    end

    expect(offenders).to eq([])
  end

  describe "the new-issue popup after creating an issue" do
    def create_issue_returning(url)
      allow(RailsErrorDashboard::Commands::CreateIssue).to receive(:call)
        .and_return({ success: true, issue_url: url })
      post "/error_dashboard/errors/#{error.id}/create_issue"
      follow_redirect!
    end

    it "does not open a URL that is not http(s)" do
      create_issue_returning("javascript:window.__PWN=1")

      expect(response.body).not_to include("window.open(")
    end

    it "still opens an https URL" do
      create_issue_returning("https://github.com/a/b/issues/9")

      expect(response.body).to include("window.open('https://github.com/a/b/issues/9'")
    end
  end
end
