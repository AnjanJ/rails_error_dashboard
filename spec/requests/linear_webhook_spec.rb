# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Linear webhooks", type: :request do
  let(:secret) { "linear-webhook-secret" }
  let!(:error_log) do
    create(:error_log,
      occurred_at: 1.day.ago,
      external_issue_provider: "linear",
      external_issue_number: 42,
      external_issue_url: "https://linear.app/acme/issue/ENG-42/boom")
  end

  before do
    RailsErrorDashboard.configuration.enable_issue_tracking = true
    RailsErrorDashboard.configuration.issue_webhook_secret = secret
  end

  after do
    RailsErrorDashboard.configuration.enable_issue_tracking = false
    RailsErrorDashboard.configuration.issue_webhook_secret = nil
  end

  def post_webhook(payload, sign_with: secret)
    body = payload.to_json
    post "/error_dashboard/webhooks/linear",
      params: body,
      headers: {
        "Content-Type" => "application/json",
        "Linear-Signature" => OpenSSL::HMAC.hexdigest("SHA256", sign_with, body)
      }
  end

  def state_change_payload(state_type:, action: "update")
    {
      type: "Issue",
      action: action,
      actor: { name: "Dev One" },
      data: { number: 42, state: { name: "Done", type: state_type } },
      updatedFrom: { stateId: "old-state-uuid" }
    }
  end

  it "resolves the error when the issue moves to a completed state" do
    post_webhook(state_change_payload(state_type: "completed"))

    expect(response).to have_http_status(:ok)
    expect(error_log.reload.resolved).to be true
  end

  it "resolves the error when the issue is canceled" do
    post_webhook(state_change_payload(state_type: "canceled"))

    expect(error_log.reload.resolved).to be true
  end

  it "reopens a resolved error when the issue moves back to unstarted" do
    error_log.update!(resolved: true, resolved_at: Time.current, status: "resolved")

    post_webhook(state_change_payload(state_type: "unstarted"))

    expect(response).to have_http_status(:ok)
    error_log.reload
    expect(error_log.resolved).to be false
    expect(error_log.status).to eq("new")
  end

  it "ignores updates that do not change state" do
    payload = state_change_payload(state_type: "completed")
    payload[:updatedFrom] = { title: "Old title" }

    post_webhook(payload)

    expect(response).to have_http_status(:ok)
    expect(error_log.reload.resolved).to be false
  end

  it "ignores non-Issue events" do
    post_webhook({ type: "Comment", action: "update", data: { number: 42 } })

    expect(error_log.reload.resolved).to be false
  end

  it "rejects requests with an invalid signature" do
    post_webhook(state_change_payload(state_type: "completed"), sign_with: "wrong-secret")

    expect(response).to have_http_status(:unauthorized)
    expect(error_log.reload.resolved).to be false
  end

  it "rejects requests without a signature header" do
    post "/error_dashboard/webhooks/linear",
      params: state_change_payload(state_type: "completed").to_json,
      headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end
end
