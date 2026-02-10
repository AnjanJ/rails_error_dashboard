# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::ApplicationHelper, type: :helper do
  describe "#auto_link_urls" do
    before do
      RailsErrorDashboard.configuration.git_repository_url = nil
    end

    context "with blank text" do
      it "returns empty string for nil" do
        expect(helper.auto_link_urls(nil)).to eq("")
      end

      it "returns empty string for empty string" do
        expect(helper.auto_link_urls("")).to eq("")
      end
    end

    context "with plain text" do
      it "returns the text wrapped in paragraph tags" do
        result = helper.auto_link_urls("hello world")
        expect(result).to include("hello world")
      end
    end

    context "with URLs" do
      it "converts https URLs to clickable links" do
        result = helper.auto_link_urls("check https://example.com/path for details")
        expect(result).to include('href="https://example.com/path"')
        expect(result).to include('target="_blank"')
        expect(result).to include('rel="noopener noreferrer"')
      end

      it "converts http URLs to clickable links" do
        result = helper.auto_link_urls("see http://example.com")
        expect(result).to include('href="http://example.com"')
      end
    end

    context "with inline code in backticks" do
      it "highlights inline code with code tags" do
        result = helper.auto_link_urls("run `bundle install` first")
        expect(result).to include("<code")
        expect(result).to include("bundle install")
        expect(result).to include("inline-code-highlight")
      end
    end

    context "with file paths in backticks" do
      before do
        RailsErrorDashboard.configuration.git_repository_url = "https://github.com/test/repo"
      end

      it "converts file paths to GitHub links when repo URL is configured" do
        result = helper.auto_link_urls("check `app/models/user.rb` for the issue")
        expect(result).to include("https://github.com/test/repo/blob/main/app/models/user.rb")
        expect(result).to include("file-path-link")
      end

      it "does not convert file paths when no repo URL is configured" do
        RailsErrorDashboard.configuration.git_repository_url = nil
        result = helper.auto_link_urls("check `app/models/user.rb` for the issue")
        expect(result).not_to include("github.com")
        expect(result).to include("app/models/user.rb")
      end
    end

    context "with error parameter" do
      let(:error_log) { create(:error_log) }

      it "does not crash when application lacks repository_url column" do
        # This was the bug: Application model has no repository_url column,
        # calling error.application.repository_url raised NoMethodError
        expect {
          helper.auto_link_urls("some comment text", error: error_log)
        }.not_to raise_error
      end

      it "falls back to global config when application has no repository_url" do
        RailsErrorDashboard.configuration.git_repository_url = "https://github.com/test/repo"
        result = helper.auto_link_urls("see `app/models/user.rb`", error: error_log)
        expect(result).to include("https://github.com/test/repo/blob/main/app/models/user.rb")
      end

      it "works when error is passed without error parameter" do
        expect {
          helper.auto_link_urls("comment text", error: nil)
        }.not_to raise_error
      end
    end

    context "with nil error" do
      it "works without error parameter" do
        result = helper.auto_link_urls("plain text")
        expect(result).to include("plain text")
      end
    end

    context "HTML escaping in code blocks" do
      it "escapes HTML inside inline code backticks" do
        result = helper.auto_link_urls("run `<img onerror=alert(1)>` carefully")
        expect(result).to include("&lt;img")
        expect(result).not_to include("<img onerror")
      end
    end
  end
end
