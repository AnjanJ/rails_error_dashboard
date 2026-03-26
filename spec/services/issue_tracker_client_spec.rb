# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::IssueTrackerClient do
  describe ".for" do
    it "returns GitHubIssueClient for :github" do
      client = described_class.for(:github, token: "tok", repo: "user/repo")
      expect(client).to be_a(RailsErrorDashboard::Services::GitHubIssueClient)
    end

    it "returns GitLabIssueClient for :gitlab" do
      client = described_class.for(:gitlab, token: "tok", repo: "user/repo")
      expect(client).to be_a(RailsErrorDashboard::Services::GitLabIssueClient)
    end

    it "returns CodebergIssueClient for :codeberg" do
      client = described_class.for(:codeberg, token: "tok", repo: "user/repo")
      expect(client).to be_a(RailsErrorDashboard::Services::CodebergIssueClient)
    end

    it "accepts string provider name" do
      client = described_class.for("github", token: "tok", repo: "user/repo")
      expect(client).to be_a(RailsErrorDashboard::Services::GitHubIssueClient)
    end

    it "raises ArgumentError for unknown provider" do
      expect { described_class.for(:bitbucket, token: "tok", repo: "user/repo") }
        .to raise_error(ArgumentError, /Unknown issue tracker provider/)
    end
  end

  describe ".from_config" do
    after { RailsErrorDashboard.reset_configuration! }

    it "returns nil when issue tracking is disabled" do
      RailsErrorDashboard.configuration.enable_issue_tracking = false
      expect(described_class.from_config).to be_nil
    end

    it "returns nil when token is missing" do
      RailsErrorDashboard.configuration.enable_issue_tracking = true
      RailsErrorDashboard.configuration.git_repository_url = "https://github.com/user/repo"
      RailsErrorDashboard.configuration.issue_tracker_token = nil
      expect(described_class.from_config).to be_nil
    end

    it "returns client when fully configured" do
      RailsErrorDashboard.configuration.enable_issue_tracking = true
      RailsErrorDashboard.configuration.git_repository_url = "https://github.com/user/repo"
      RailsErrorDashboard.configuration.issue_tracker_token = "ghp_test123"
      client = described_class.from_config
      expect(client).to be_a(RailsErrorDashboard::Services::GitHubIssueClient)
    end

    it "auto-detects GitLab from git_repository_url" do
      RailsErrorDashboard.configuration.enable_issue_tracking = true
      RailsErrorDashboard.configuration.git_repository_url = "https://gitlab.com/user/repo"
      RailsErrorDashboard.configuration.issue_tracker_token = "glpat_test"
      client = described_class.from_config
      expect(client).to be_a(RailsErrorDashboard::Services::GitLabIssueClient)
    end

    it "auto-detects Codeberg from git_repository_url" do
      RailsErrorDashboard.configuration.enable_issue_tracking = true
      RailsErrorDashboard.configuration.git_repository_url = "https://codeberg.org/user/repo"
      RailsErrorDashboard.configuration.issue_tracker_token = "tok_test"
      client = described_class.from_config
      expect(client).to be_a(RailsErrorDashboard::Services::CodebergIssueClient)
    end
  end
end

RSpec.describe RailsErrorDashboard::Services::GitHubIssueClient do
  let(:client) { described_class.new(token: "ghp_test", repo: "AnjanJ/test-repo") }

  describe "#create_issue" do
    it "sends POST to GitHub issues endpoint" do
      stub_request(:post, "https://api.github.com/repos/AnjanJ/test-repo/issues")
        .with(
          body: hash_including("title" => "NoMethodError", "labels" => [ "bug" ]),
          headers: { "Authorization" => "Bearer ghp_test" }
        )
        .to_return(status: 201, body: { html_url: "https://github.com/AnjanJ/test-repo/issues/42", number: 42 }.to_json)

      result = client.create_issue(title: "NoMethodError", body: "Error details", labels: [ "bug" ])
      expect(result[:success]).to be true
      expect(result[:url]).to eq("https://github.com/AnjanJ/test-repo/issues/42")
      expect(result[:number]).to eq(42)
    end

    it "returns error on API failure" do
      stub_request(:post, "https://api.github.com/repos/AnjanJ/test-repo/issues")
        .to_return(status: 422, body: { message: "Validation Failed" }.to_json)

      result = client.create_issue(title: "Test", body: "Body", labels: [])
      expect(result[:success]).to be false
      expect(result[:error]).to include("422")
    end
  end

  describe "#close_issue" do
    it "sends PATCH with state closed" do
      stub_request(:patch, "https://api.github.com/repos/AnjanJ/test-repo/issues/42")
        .with(body: hash_including("state" => "closed"))
        .to_return(status: 200, body: {}.to_json)

      result = client.close_issue(number: 42)
      expect(result[:success]).to be true
    end
  end

  describe "#reopen_issue" do
    it "sends PATCH with state open" do
      stub_request(:patch, "https://api.github.com/repos/AnjanJ/test-repo/issues/42")
        .with(body: hash_including("state" => "open"))
        .to_return(status: 200, body: {}.to_json)

      result = client.reopen_issue(number: 42)
      expect(result[:success]).to be true
    end
  end

  describe "#add_comment" do
    it "sends POST to comments endpoint" do
      stub_request(:post, "https://api.github.com/repos/AnjanJ/test-repo/issues/42/comments")
        .to_return(status: 201, body: { html_url: "https://github.com/AnjanJ/test-repo/issues/42#issuecomment-123" }.to_json)

      result = client.add_comment(number: 42, body: "Error recurred")
      expect(result[:success]).to be true
      expect(result[:url]).to include("issuecomment")
    end
  end

  describe "#fetch_comments" do
    it "returns formatted comments" do
      stub_request(:get, /api.github.com\/repos\/AnjanJ\/test-repo\/issues\/42\/comments/)
        .to_return(status: 200, body: [
          { user: { login: "dev1", avatar_url: "https://avatar.url/1" }, body: "Looking into this", created_at: "2026-03-25T10:00:00Z", html_url: "https://github.com/..." }
        ].to_json)

      result = client.fetch_comments(number: 42)
      expect(result[:success]).to be true
      expect(result[:comments].size).to eq(1)
      expect(result[:comments].first[:author]).to eq("dev1")
    end
  end

  describe "network error handling" do
    it "returns error on timeout" do
      stub_request(:post, "https://api.github.com/repos/AnjanJ/test-repo/issues")
        .to_timeout

      result = client.create_issue(title: "Test", body: "Body", labels: [])
      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    end
  end
end

RSpec.describe RailsErrorDashboard::Services::GitLabIssueClient do
  let(:client) { described_class.new(token: "glpat_test", repo: "user/repo") }

  describe "#create_issue" do
    it "sends POST to GitLab issues endpoint with URL-encoded project" do
      stub_request(:post, "https://gitlab.com/api/v4/projects/user%2Frepo/issues")
        .with(
          body: hash_including("title" => "NoMethodError"),
          headers: { "PRIVATE-TOKEN" => "glpat_test" }
        )
        .to_return(status: 201, body: { web_url: "https://gitlab.com/user/repo/-/issues/7", iid: 7 }.to_json)

      result = client.create_issue(title: "NoMethodError", body: "Details", labels: [ "bug" ])
      expect(result[:success]).to be true
      expect(result[:url]).to include("gitlab.com")
      expect(result[:number]).to eq(7)
    end
  end

  describe "#close_issue" do
    it "sends PUT with state_event close" do
      stub_request(:put, "https://gitlab.com/api/v4/projects/user%2Frepo/issues/7")
        .with(body: hash_including("state_event" => "close"))
        .to_return(status: 200, body: {}.to_json)

      result = client.close_issue(number: 7)
      expect(result[:success]).to be true
    end
  end
end

RSpec.describe RailsErrorDashboard::Services::CodebergIssueClient do
  let(:client) { described_class.new(token: "tok_test", repo: "user/repo") }

  describe "#create_issue" do
    it "sends POST to Codeberg/Gitea API endpoint" do
      stub_request(:post, "https://codeberg.org/api/v1/repos/user/repo/issues")
        .with(
          body: hash_including("title" => "NoMethodError"),
          headers: { "Authorization" => "token tok_test" }
        )
        .to_return(status: 201, body: { html_url: "https://codeberg.org/user/repo/issues/3", number: 3 }.to_json)

      result = client.create_issue(title: "NoMethodError", body: "Details", labels: [])
      expect(result[:success]).to be true
      expect(result[:url]).to include("codeberg.org")
      expect(result[:number]).to eq(3)
    end
  end

  describe "custom API URL for self-hosted Gitea" do
    it "uses the custom API URL" do
      custom_client = described_class.new(token: "tok", repo: "org/app", api_url: "https://git.mycompany.com/api/v1")

      stub_request(:post, "https://git.mycompany.com/api/v1/repos/org/app/issues")
        .to_return(status: 201, body: { html_url: "https://git.mycompany.com/org/app/issues/1", number: 1 }.to_json)

      result = custom_client.create_issue(title: "Test", body: "Body", labels: [])
      expect(result[:success]).to be true
      expect(result[:url]).to include("git.mycompany.com")
    end
  end
end
