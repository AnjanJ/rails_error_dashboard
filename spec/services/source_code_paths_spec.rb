# frozen_string_literal: true

require "rails_helper"

# The source viewer's path handling: which frames are the host's, how a frame
# is stored relative to Rails.root, and how it maps to a repository link.
RSpec.describe "Source code paths" do
  describe RailsErrorDashboard::Services::BacktraceParser do
    def category(path)
      described_class.new("#{path}:1:in `x'").parse.first[:category]
    end

    it "does not call an engine gem's app/ or lib/ the host's code" do
      expect(category("gems/devise-4.9.4/app/controllers/devise/sessions_controller.rb")).to eq(:gem)
      expect(category("/srv/vendor/bundle/ruby/3.3.0/gems/foo-1.0/lib/foo.rb")).to eq(:gem)
      expect(category("gems/foo-1.0/lib/foo.rb")).to eq(:gem)
    end

    it "keeps the host's app/, lib/, config/ and db/ frames as app code" do
      expect(category("app/models/user.rb")).to eq(:app)
      expect(category("lib/tasks/thing.rb")).to eq(:app)
      expect(category("config/initializers/x.rb")).to eq(:app)
      expect(category("/srv/myapp/app/models/user.rb")).to eq(:app)
    end
  end

  describe RailsErrorDashboard::Services::BacktraceProcessor do
    before { allow(Rails).to receive(:root).and_return(Pathname.new("/app")) }

    # /app/lib/foo.rb became app/lib/foo.rb, which the reader then looked for
    # at /app/app/lib/foo.rb.
    it "stores a frame under a Rails.root named /app relative to the root" do
      expect(described_class.shorten_gem_path("/app/lib/foo.rb:3:in `bar'")).to eq("lib/foo.rb:3:in `bar'")
      expect(described_class.shorten_gem_path("/app/app/models/user.rb:3:in `bar'")).to eq("app/models/user.rb:3:in `bar'")
      expect(described_class.shorten_gem_path("/app/config/initializers/x.rb:1:in `<main>'")).to eq("config/initializers/x.rb:1:in `<main>'")
    end

    it "still shortens gem and stdlib frames first" do
      expect(described_class.shorten_gem_path("/app/vendor/bundle/ruby/3.3.0/gems/foo-1.0/lib/foo.rb:1")).to eq("gems/foo-1.0/lib/foo.rb:1")
      expect(described_class.shorten_gem_path("/usr/local/lib/ruby/3.3.0/net/http.rb:1")).to eq("ruby/3.3.0/net/http.rb:1")
    end
  end

  describe RailsErrorDashboard::Services::GithubLinkGenerator do
    def link_path(path)
      url = described_class.new(repository_url: "https://github.com/o/r", file_path: path, line_number: 7, commit_sha: "abc").generate_link
      url.to_s.sub(%r{\A.*/blob/[^/]+/}, "").sub(/#L7\z/, "")
    end

    # The greedy match took the LAST app|lib|config|... segment of a path
    # that was already relative to Rails.root.
    it "links a root-relative path to its first Rails directory, not the last" do
      expect(link_path("app/services/config/loader.rb")).to eq("app/services/config/loader.rb")
      expect(link_path("app/models/contest/x.rb")).to eq("app/models/contest/x.rb")
      expect(link_path("lib/tasks/test/x.rb")).to eq("lib/tasks/test/x.rb")
    end

    it "strips Rails.root from an absolute path before looking for a Rails directory" do
      allow(Rails).to receive(:root).and_return(Pathname.new("/srv/current"))

      expect(link_path("/srv/current/app/services/config/loader.rb")).to eq("app/services/config/loader.rb")
      # Unknown root: the last standard directory is still the best guess.
      expect(link_path("/home/deploy/current/app/models/x.rb")).to eq("app/models/x.rb")
    end
  end

  describe RailsErrorDashboard::BacktraceHelper, "#repository_host_label", type: :helper do
    it "names the host from the URL's host, not from the whole URL" do
      expect(helper.repository_host_label("https://github.com/o/r/blob/main/x.rb")).to eq("GitHub")
      expect(helper.repository_host_label("https://gitlab.example.com/o/r/-/blob/main/x.rb")).to eq("GitLab")
      expect(helper.repository_host_label("https://codeberg.org/o/r/src/branch/main/x.rb")).to eq("Codeberg")
      expect(helper.repository_host_label("https://bitbucket.org/o/r/src/main/x.rb")).to eq("Bitbucket")
      expect(helper.repository_host_label("https://git.example.com/o/github-tools/x.rb")).to eq("git.example.com")
      expect(helper.repository_host_label("not a url")).to eq("Repository")
    end
  end
end
