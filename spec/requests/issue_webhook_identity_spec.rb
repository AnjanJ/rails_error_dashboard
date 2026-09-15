# frozen_string_literal: true

require "rails_helper"

# A linked issue's identity is provider + number + REPOSITORY.
#
# It used to be provider + number alone, so issue 42 in acme/api and issue 42
# in acme/web were indistinguishable: a validly signed webhook from one
# repository resolved the error linked to the other. Not a signature bypass --
# the request is genuine -- but it acts on the wrong error. It matters for
# shared databases, several linked repositories, a repository rename, and
# Linear, where issue numbers are scoped per team and collide constantly.
RSpec.describe "issue webhook identity", type: :request do
  let(:secret) { "identity-webhook-secret" }

  before do
    RailsErrorDashboard.configuration.enable_issue_tracking = true
    RailsErrorDashboard.configuration.issue_webhook_secret = secret
    RailsErrorDashboard.configuration.issue_tracker_token = nil
  end

  after { RailsErrorDashboard.reset_configuration! }

  def linked(repo:, number: 42, provider: "github", url: nil)
    create(:error_log,
      occurred_at: 1.hour.ago,
      external_issue_provider: provider,
      external_issue_number: number,
      external_issue_repo: repo,
      external_issue_url: url || "https://github.com/#{repo}/issues/#{number}",
      resolved: false,
      status: "new")
  end

  def post_github(payload)
    body = payload.to_json
    post "/error_dashboard/webhooks/github",
      params: body,
      headers: {
        "Content-Type" => "application/json",
        "X-Hub-Signature-256" => "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, body)
      }
  end

  def close_payload(repo:, number: 42)
    {
      action: "closed",
      issue: { number: number, html_url: "https://github.com/#{repo}/issues/#{number}" },
      repository: { full_name: repo },
      sender: { login: "someone" }
    }
  end

  it "does not resolve an error linked to a different repository" do
    other_repo = linked(repo: "acme/api")

    post_github(close_payload(repo: "acme/web"))

    expect(response).to have_http_status(:ok)
    expect(other_repo.reload).not_to be_resolved
  end

  it "resolves the error linked to the repository the webhook came from" do
    api = linked(repo: "acme/api")
    web = linked(repo: "acme/web")

    post_github(close_payload(repo: "acme/web"))

    expect(web.reload).to be_resolved
    expect(api.reload).not_to be_resolved
  end

  # Rows linked before the repository was recorded have NULL there. Their
  # stored URL is corroborating evidence for which repository the link was
  # made against.
  describe "rows linked before repositories were recorded" do
    it "matches when the stored URL agrees with the payload, and adopts the identity" do
      legacy = create(:error_log, occurred_at: 1.hour.ago,
        external_issue_provider: "github", external_issue_number: 77,
        external_issue_repo: nil,
        external_issue_url: "https://github.com/acme/api/issues/77",
        resolved: false, status: "new")

      post_github(close_payload(repo: "acme/api", number: 77))

      legacy.reload
      expect(legacy).to be_resolved
      expect(legacy.external_issue_repo).to eq("acme/api")
    end

    # The residual of the original defect if adoption were unconditional: the
    # first webhook to name ANY repository would claim the row.
    it "does NOT match when the stored URL names a different repository" do
      legacy = create(:error_log, occurred_at: 1.hour.ago,
        external_issue_provider: "github", external_issue_number: 77,
        external_issue_repo: nil,
        external_issue_url: "https://github.com/acme/api/issues/77",
        resolved: false, status: "new")

      post_github(close_payload(repo: "acme/web", number: 77))

      legacy.reload
      expect(legacy).not_to be_resolved
      expect(legacy.external_issue_repo).to be_nil
    end

    # An unrecognised forge leaves no evidence either way; dropping the event
    # would break a link that works today.
    it "still matches leniently when the stored URL cannot be parsed" do
      legacy = create(:error_log, occurred_at: 1.hour.ago,
        external_issue_provider: "github", external_issue_number: 77,
        external_issue_repo: nil,
        external_issue_url: "https://git.internal.example/odd/shape/77",
        resolved: false, status: "new")

      post_github(close_payload(repo: "acme/api", number: 77))

      legacy.reload
      expect(legacy).to be_resolved
      expect(legacy.external_issue_repo).to eq("acme/api")
    end
  end

  describe "Linear, where numbers are scoped per team" do
    def post_linear(team_key:, number: 42)
      body = {
        type: "Issue",
        action: "update",
        actor: { name: "Dev" },
        data: { number: number, team: { key: team_key }, state: { name: "Done", type: "completed" } },
        updatedFrom: { stateId: "old" }
      }.to_json

      post "/error_dashboard/webhooks/linear",
        params: body,
        headers: {
          "Content-Type" => "application/json",
          "Linear-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, body)
        }
    end

    it "does not resolve another team's issue with the same number" do
      eng = create(:error_log, occurred_at: 1.hour.ago, external_issue_provider: "linear",
        external_issue_number: 42, external_issue_repo: "ENG",
        external_issue_url: "https://linear.app/acme/issue/ENG-42/x", resolved: false, status: "new")

      post_linear(team_key: "OPS")

      expect(eng.reload).not_to be_resolved
    end

    it "resolves its own team's issue" do
      ops = create(:error_log, occurred_at: 1.hour.ago, external_issue_provider: "linear",
        external_issue_number: 42, external_issue_repo: "OPS",
        external_issue_url: "https://linear.app/acme/issue/OPS-42/x", resolved: false, status: "new")

      post_linear(team_key: "OPS")

      expect(ops.reload).to be_resolved
    end
  end

  describe "the identity is recorded when a link is made" do
    let(:error) { create(:error_log, occurred_at: 1.hour.ago) }

    it "keeps the repository LinkExistingIssue parses out of the URL" do
      RailsErrorDashboard::Commands::LinkExistingIssue.call(
        error.id, issue_url: "https://github.com/acme/api/issues/42"
      )

      expect(error.reload.external_issue_repo).to eq("acme/api")
    end

    it "records a Linear team key upper-cased, as Linear reports it" do
      RailsErrorDashboard::Commands::LinkExistingIssue.call(
        error.id, issue_url: "https://linear.app/acme/issue/eng-123/payment"
      )

      expect(error.reload.external_issue_repo).to eq("ENG")
    end
  end

  # An outbound comment or close must reach the repository the issue was opened
  # in, not whatever the global configuration currently points at.
  describe "outbound clients use the linked identity" do
    it "builds a client for the error's own repository" do
      RailsErrorDashboard.configuration.issue_tracker_provider = :github
      RailsErrorDashboard.configuration.issue_tracker_token = "ghp_test"
      RailsErrorDashboard.configuration.issue_tracker_repo = "acme/web"

      error = linked(repo: "acme/api")
      client = RailsErrorDashboard::Services::IssueTrackerClient.for_error(error)

      expect(client.repo).to eq("acme/api")
    end

    it "falls back to configuration for a row with no recorded repository" do
      RailsErrorDashboard.configuration.issue_tracker_provider = :github
      RailsErrorDashboard.configuration.issue_tracker_token = "ghp_test"
      RailsErrorDashboard.configuration.issue_tracker_repo = "acme/web"

      error = linked(repo: nil)
      client = RailsErrorDashboard::Services::IssueTrackerClient.for_error(error)

      expect(client.repo).to eq("acme/web")
    end
  end
end
