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

    # The stored URL is rendered as an href on the error page, so anything
    # that is not plain http(s) has to be refused at write time.
    describe "URL scheme validation" do
      {
        "a javascript: URL" => "javascript:window.x=1",
        "a mixed-case javascript: URL" => "JaVaScRiPt:alert(1)",
        "a javascript: URL behind a leading space" => " javascript:window.x=1",
        "a javascript: URL split by a TAB" => "java\tscript:alert(1)",
        "an https URL containing a newline" => "https://github.com/a/b/issues/1\njavascript:alert(1)",
        "a data: URL" => "data:text/html,x",
        "a vbscript: URL" => "vbscript:x",
        "a protocol-relative URL" => "//evil.example/issues/1",
        "a relative path" => "/relative/issues/1",
        "an ftp URL" => "ftp://h/issues/1",
        "an https URL with no host" => "https://",
        "an unparseable URL" => "https://exa mple.com/issues/1"
      }.each do |label, url|
        it "rejects #{label} and leaves the record untouched" do
          result = described_class.call(error_log.id, issue_url: url)

          expect(result[:success]).to be false
          expect(result[:error]).to eq(I18n.t("red.commands.issue.url_invalid"))
          error_log.reload
          expect(error_log.external_issue_url).to be_nil
          expect(error_log.external_issue_number).to be_nil
        end
      end

      it "does not overwrite an existing link when the new URL is rejected" do
        error_log.update!(external_issue_url: "https://github.com/a/b/issues/1")

        described_class.call(error_log.id, issue_url: "javascript:window.x=1")

        expect(error_log.reload.external_issue_url).to eq("https://github.com/a/b/issues/1")
      end

      it "accepts an https URL" do
        result = described_class.call(error_log.id, issue_url: "https://github.com/a/b/issues/1")

        expect(result[:success]).to be true
        expect(error_log.reload.external_issue_url).to eq("https://github.com/a/b/issues/1")
      end

      it "accepts an upper-case HTTP scheme on a self-hosted forge" do
        result = described_class.call(error_log.id, issue_url: "HTTP://gitlab.example.com/a/b/-/issues/2")

        expect(result[:success]).to be true
        expect(error_log.reload.external_issue_number).to eq(2)
      end
    end
  end
end
