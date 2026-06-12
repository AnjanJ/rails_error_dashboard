# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::LinkExistingIssue do
  let(:error_log) { create(:error_log, occurred_at: 1.day.ago) }

  describe ".call" do
    it "links a GitHub issue URL" do
      result = described_class.call(error_log.id, issue_url: "https://github.com/user/repo/issues/42")

      expect(result[:success]).to be true
      error_log.reload
      expect(error_log.external_issue_url).to eq("https://github.com/user/repo/issues/42")
      expect(error_log.external_issue_number).to eq(42)
      expect(error_log.external_issue_provider).to eq("github")
    end

    it "links a GitLab issue URL" do
      result = described_class.call(error_log.id, issue_url: "https://gitlab.com/user/repo/-/issues/7")

      expect(result[:success]).to be true
      error_log.reload
      expect(error_log.external_issue_number).to eq(7)
      expect(error_log.external_issue_provider).to eq("gitlab")
    end

    it "links a Codeberg issue URL" do
      result = described_class.call(error_log.id, issue_url: "https://codeberg.org/user/repo/issues/3")

      expect(result[:success]).to be true
      error_log.reload
      expect(error_log.external_issue_number).to eq(3)
      expect(error_log.external_issue_provider).to eq("codeberg")
    end

    it "links a Linear issue URL" do
      result = described_class.call(error_log.id, issue_url: "https://linear.app/acme/issue/ENG-123/payment-error")

      expect(result[:success]).to be true
      error_log.reload
      expect(error_log.external_issue_number).to eq(123)
      expect(error_log.external_issue_provider).to eq("linear")
    end

    it "handles unknown provider URLs gracefully" do
      result = described_class.call(error_log.id, issue_url: "https://git.mycompany.com/org/app/issues/15")

      expect(result[:success]).to be true
      error_log.reload
      expect(error_log.external_issue_url).to eq("https://git.mycompany.com/org/app/issues/15")
      expect(error_log.external_issue_number).to eq(15)
      expect(error_log.external_issue_provider).to be_nil
    end

    it "returns error for blank URL" do
      result = described_class.call(error_log.id, issue_url: "")
      expect(result[:success]).to be false
      expect(result[:error]).to include("required")
    end

    it "returns error for non-existent error" do
      result = described_class.call(999_999, issue_url: "https://github.com/user/repo/issues/1")
      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end

    it "strips whitespace from URL" do
      result = described_class.call(error_log.id, issue_url: "  https://github.com/user/repo/issues/42  ")

      expect(result[:success]).to be true
      error_log.reload
      expect(error_log.external_issue_url).to eq("https://github.com/user/repo/issues/42")
    end
  end
end
