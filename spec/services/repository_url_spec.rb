# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-0/REQ-3: the link generator stripped ".git" before the
# trailing slash, so ".git/" kept its ".git"; the issue tracker's regex failed on
# any trailing slash, which silently turned issue tracking off.
RSpec.describe RailsErrorDashboard::Services::RepositoryUrl do
  variants = [
    "https://github.com/u/r",
    "https://github.com/u/r.git",
    "https://github.com/u/r.git/",
    "https://github.com/u/r/",
    "https://github.com/u/r//",
    "  https://github.com/u/r.git  "
  ]

  describe ".normalize" do
    variants.each do |url|
      it "normalizes #{url.inspect}" do
        expect(described_class.normalize(url)).to eq("https://github.com/u/r")
      end
    end

    it "returns nil for nil" do
      expect(described_class.normalize(nil)).to be_nil
    end
  end

  describe "the View Source link" do
    variants.each do |url|
      it "links into the repository for #{url.inspect}" do
        link = RailsErrorDashboard::Services::GithubLinkGenerator.new(
          repository_url: url, file_path: "app/models/user.rb", line_number: 3, commit_sha: "abc123"
        ).generate_link

        expect(link).to eq("https://github.com/u/r/blob/abc123/app/models/user.rb#L3")
      end
    end
  end

  describe "the issue tracker repository" do
    variants.each do |url|
      it "is u/r for #{url.inspect}" do
        config = RailsErrorDashboard::Configuration.new
        config.git_repository_url = url

        expect(config.effective_issue_tracker_repo).to eq("u/r")
      end
    end
  end
end
