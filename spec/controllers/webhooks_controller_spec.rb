# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::WebhooksController, type: :controller do
  routes { RailsErrorDashboard::Engine.routes }

  let(:secret) { "test_webhook_secret_123" }
  let(:error_log) do
    create(:error_log,
      occurred_at: 1.day.ago,
      external_issue_url: "https://github.com/user/repo/issues/42",
      external_issue_number: 42,
      external_issue_provider: "github"
    )
  end

  before do
    RailsErrorDashboard.configuration.enable_issue_tracking = true
    RailsErrorDashboard.configuration.issue_webhook_secret = secret
  end

  after { RailsErrorDashboard.reset_configuration! }

  describe "POST #receive" do
    context "when webhooks are disabled" do
      before { RailsErrorDashboard.configuration.enable_issue_tracking = false }

      it "returns 404" do
        post :receive, params: { provider: "github" }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when no secret is configured" do
      before { RailsErrorDashboard.configuration.issue_webhook_secret = nil }

      it "returns 404 (webhooks inactive without secret)" do
        post :receive, params: { provider: "github" }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "GitHub webhook" do
      def github_signature(body)
        "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, body)
      end

      it "resolves error when issue is closed" do
        error_log # create
        payload = { action: "closed", issue: { number: 42 }, sender: { login: "dev1" } }.to_json

        request.headers["X-Hub-Signature-256"] = github_signature(payload)
        request.headers["Content-Type"] = "application/json"

        post :receive, params: { provider: "github" }, body: payload

        expect(response).to have_http_status(:ok)
        error_log.reload
        expect(error_log.resolved).to be true
      end

      it "reopens error when issue is reopened" do
        error_log.update!(resolved: true, resolved_at: Time.current, status: "resolved")
        payload = { action: "reopened", issue: { number: 42 }, sender: { login: "dev1" } }.to_json

        request.headers["X-Hub-Signature-256"] = github_signature(payload)
        request.headers["Content-Type"] = "application/json"

        post :receive, params: { provider: "github" }, body: payload

        expect(response).to have_http_status(:ok)
        error_log.reload
        expect(error_log.resolved).to be false
      end

      it "returns 401 with invalid signature" do
        payload = { action: "closed", issue: { number: 42 } }.to_json
        request.headers["X-Hub-Signature-256"] = "sha256=invalid"
        request.headers["Content-Type"] = "application/json"

        post :receive, params: { provider: "github" }, body: payload
        expect(response).to have_http_status(:unauthorized)
      end

      it "ignores non-close/reopen actions" do
        payload = { action: "opened", issue: { number: 42 } }.to_json
        request.headers["X-Hub-Signature-256"] = github_signature(payload)
        request.headers["Content-Type"] = "application/json"

        post :receive, params: { provider: "github" }, body: payload
        expect(response).to have_http_status(:ok)
        error_log.reload
        expect(error_log.resolved).to be false
      end
    end

    context "GitLab webhook" do
      it "resolves error when issue is closed" do
        error_log.update!(external_issue_provider: "gitlab")
        payload = {
          object_attributes: { action: "close", iid: 42 },
          user: { username: "dev1" }
        }.to_json

        request.headers["X-Gitlab-Token"] = secret
        request.headers["Content-Type"] = "application/json"

        post :receive, params: { provider: "gitlab" }, body: payload
        expect(response).to have_http_status(:ok)
        error_log.reload
        expect(error_log.resolved).to be true
      end
    end

    context "Codeberg webhook" do
      def codeberg_signature(body)
        OpenSSL::HMAC.hexdigest("SHA256", secret, body)
      end

      it "resolves error when issue is closed" do
        error_log.update!(external_issue_provider: "codeberg")
        payload = { action: "closed", issue: { number: 42 }, sender: { login: "dev1" } }.to_json

        request.headers["X-Gitea-Signature"] = codeberg_signature(payload)
        request.headers["Content-Type"] = "application/json"

        post :receive, params: { provider: "codeberg" }, body: payload
        expect(response).to have_http_status(:ok)
        error_log.reload
        expect(error_log.resolved).to be true
      end
    end

    # audit-fixes-0-16-0/REQ-10: the signature check ran first and answered
    # 401, so a Gitea user posting to /webhooks/gitea was told the signature
    # was wrong when the provider name was.
    context "unknown provider" do
      it "returns 404" do
        payload = {}.to_json
        request.headers["Content-Type"] = "application/json"

        post :receive, params: { provider: "bitbucket" }, body: payload

        expect(response).to have_http_status(:not_found)
      end

      it "still answers 401 to a known provider with a bad signature" do
        request.headers["Content-Type"] = "application/json"
        request.headers["X-Hub-Signature-256"] = "sha256=wrong"

        post :receive, params: { provider: "github" }, body: {}.to_json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
