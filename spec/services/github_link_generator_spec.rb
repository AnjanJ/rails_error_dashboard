# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::GithubLinkGenerator do
  describe "#generate_link" do
    context "GitHub repositories" do
      it "generates link with commit SHA" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123def456"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123def456/app/models/user.rb#L42")
      end

      it "generates link with branch name when no commit SHA" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42,
          branch: "develop"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/develop/app/models/user.rb#L42")
      end

      it "defaults to main branch when no commit SHA or branch" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/main/app/models/user.rb#L42")
      end

      it "handles repository URL with .git suffix" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo.git",
          file_path: "app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/app/models/user.rb#L42")
      end

      it "handles repository URL with trailing slash" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo/",
          file_path: "app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/app/models/user.rb#L42")
      end

      it "handles file paths with leading slash" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "/app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/app/models/user.rb#L42")
      end

      it "extracts relative path from absolute path" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "/Users/developer/myapp/app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/app/models/user.rb#L42")
      end

      it "handles lib/ paths" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "/Users/developer/myapp/lib/service.rb",
          line_number: 10,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/lib/service.rb#L10")
      end

      it "handles config/ paths" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "/var/www/app/config/routes.rb",
          line_number: 5,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/config/routes.rb#L5")
      end
    end

    context "GitLab repositories" do
      it "generates link with commit SHA" do
        generator = described_class.new(
          repository_url: "https://gitlab.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123def456"
        )

        link = generator.generate_link

        expect(link).to eq("https://gitlab.com/user/repo/-/blob/abc123def456/app/models/user.rb#L42")
      end

      it "generates link with branch name" do
        generator = described_class.new(
          repository_url: "https://gitlab.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42,
          branch: "feature-branch"
        )

        link = generator.generate_link

        expect(link).to eq("https://gitlab.com/user/repo/-/blob/feature-branch/app/models/user.rb#L42")
      end

      it "handles self-hosted GitLab" do
        generator = described_class.new(
          repository_url: "https://gitlab.mycompany.com/team/repo",
          file_path: "app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://gitlab.mycompany.com/team/repo/-/blob/abc123/app/models/user.rb#L42")
      end
    end

    context "Bitbucket repositories" do
      it "generates link with commit SHA" do
        generator = described_class.new(
          repository_url: "https://bitbucket.org/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123def456"
        )

        link = generator.generate_link

        expect(link).to eq("https://bitbucket.org/user/repo/src/abc123def456/app/models/user.rb#lines-42")
      end

      it "generates link with branch name" do
        generator = described_class.new(
          repository_url: "https://bitbucket.org/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42,
          branch: "master"
        )

        link = generator.generate_link

        expect(link).to eq("https://bitbucket.org/user/repo/src/master/app/models/user.rb#lines-42")
      end

      it "handles self-hosted Bitbucket" do
        generator = described_class.new(
          repository_url: "https://bitbucket.mycompany.com/projects/repo",
          file_path: "app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://bitbucket.mycompany.com/projects/repo/src/abc123/app/models/user.rb#lines-42")
      end
    end

    context "error handling" do
      it "returns nil for blank repository URL" do
        generator = described_class.new(
          repository_url: "",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        expect(generator.generate_link).to be_nil
      end

      it "returns nil for nil repository URL" do
        generator = described_class.new(
          repository_url: nil,
          file_path: "app/models/user.rb",
          line_number: 42
        )

        expect(generator.generate_link).to be_nil
      end

      it "returns nil for blank file path" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "",
          line_number: 42
        )

        expect(generator.generate_link).to be_nil
      end

      it "returns nil for nil file path" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: nil,
          line_number: 42
        )

        expect(generator.generate_link).to be_nil
      end

      it "sets error message for unsupported repository type" do
        generator = described_class.new(
          repository_url: "https://unsupported.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        link = generator.generate_link

        expect(link).to be_nil
        expect(generator.error).to eq("Unsupported repository type")
      end

      it "returns nil for a javascript: URL instead of producing a javascript href" do
        generator = described_class.new(
          repository_url: "javascript:alert(1)//github.com",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        expect(generator.generate_link).to be_nil
        expect(generator.error).to eq("Unsupported repository URL scheme: only http and https URLs are linked")
      end

      it "returns nil for an scp-style git@ URL, which can never be a web link" do
        generator = described_class.new(
          repository_url: "git@github.com:user/repo.git",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        expect(generator.generate_link).to be_nil
        expect(generator.error).to match(/only http and https/)
      end

      it "does not treat a host that merely ends in github.com as GitHub" do
        generator = described_class.new(
          repository_url: "https://github.com.example.net/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        expect(generator.generate_link).to be_nil
        expect(generator.error).to eq("Unsupported repository type")
      end

      it "does not treat github.com in the path as GitHub" do
        generator = described_class.new(
          repository_url: "https://example.net/github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        expect(generator.generate_link).to be_nil
        expect(generator.error).to eq("Unsupported repository type")
      end

      it "does not treat github.com in the userinfo as GitHub" do
        generator = described_class.new(
          repository_url: "https://github.com@example.net/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        expect(generator.generate_link).to be_nil
        expect(generator.error).to eq("Unsupported repository type")
      end

      it "still links self-hosted GitLab by its host" do
        generator = described_class.new(
          repository_url: "https://gitlab.example.net/team/app",
          file_path: "app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123"
        )

        expect(generator.generate_link).to eq("https://gitlab.example.net/team/app/-/blob/abc123/app/models/user.rb#L42")
      end

      it "handles exceptions gracefully" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        # Mock an exception in normalize_file_path
        allow(generator).to receive(:normalize_file_path).and_raise(StandardError, "Something went wrong")

        link = generator.generate_link

        expect(link).to be_nil
        expect(generator.error).to match(/Error generating link/)
      end

      it "logs errors" do
        allow(RailsErrorDashboard::Logger).to receive(:error)

        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        allow(generator).to receive(:normalize_file_path).and_raise(StandardError, "Test error")

        generator.generate_link

        expect(RailsErrorDashboard::Logger).to have_received(:error)
      end
    end

    context "line number handling" do
      it "converts string line number to integer" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: "42"
        )

        expect(generator.line_number).to eq(42)
        expect(generator.line_number).to be_a(Integer)
      end

      it "handles line number 1" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 1,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to include("#L1")
      end

      it "handles large line numbers" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 999_999,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to include("#L999999")
      end
    end

    context "repository type detection" do
      it "detects GitHub from URL" do
        generator = described_class.new(
          repository_url: "https://github.com/rails/rails",
          file_path: "app/models/user.rb",
          line_number: 1
        )

        expect(generator.send(:detect_repository_type)).to eq(:github)
      end

      it "detects GitLab from URL" do
        generator = described_class.new(
          repository_url: "https://gitlab.com/gitlab-org/gitlab",
          file_path: "app/models/user.rb",
          line_number: 1
        )

        expect(generator.send(:detect_repository_type)).to eq(:gitlab)
      end

      it "detects Bitbucket from URL" do
        generator = described_class.new(
          repository_url: "https://bitbucket.org/atlassian/repository",
          file_path: "app/models/user.rb",
          line_number: 1
        )

        expect(generator.send(:detect_repository_type)).to eq(:bitbucket)
      end

      it "detects self-hosted GitLab" do
        generator = described_class.new(
          repository_url: "https://gitlab.example.com/team/repo",
          file_path: "app/models/user.rb",
          line_number: 1
        )

        expect(generator.send(:detect_repository_type)).to eq(:gitlab)
      end

      it "returns unknown for unsupported hosts" do
        generator = described_class.new(
          repository_url: "https://sourceforge.net/projects/repo",
          file_path: "app/models/user.rb",
          line_number: 1
        )

        expect(generator.send(:detect_repository_type)).to eq(:unknown)
      end
    end

    context "reference determination" do
      it "prefers commit SHA over branch" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123",
          branch: "develop"
        )

        expect(generator.send(:determine_reference)).to eq("abc123")
      end

      it "falls back to branch when no commit SHA" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42,
          branch: "develop"
        )

        expect(generator.send(:determine_reference)).to eq("develop")
      end

      it "uses main as default branch" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "app/models/user.rb",
          line_number: 42
        )

        expect(generator.send(:determine_reference)).to eq("main")
      end
    end

    context "path normalization edge cases" do
      it "handles paths with multiple app/ occurrences" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "/home/app/myapp/app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        # Should extract from the last app/ occurrence
        expect(link).to eq("https://github.com/user/repo/blob/abc123/app/models/user.rb#L42")
      end

      it "handles spec/ paths" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "/var/www/project/spec/models/user_spec.rb",
          line_number: 10,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/spec/models/user_spec.rb#L10")
      end

      it "handles test/ paths" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "/home/deploy/app/test/models/user_test.rb",
          line_number: 15,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/test/models/user_test.rb#L15")
      end

      it "handles paths without standard Rails directories" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "custom/directory/file.rb",
          line_number: 5,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/custom/directory/file.rb#L5")
      end
    end

    context "whitespace handling" do
      it "strips whitespace from repository URL" do
        generator = described_class.new(
          repository_url: "  https://github.com/user/repo  ",
          file_path: "app/models/user.rb",
          line_number: 42,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/app/models/user.rb#L42")
      end

      it "strips whitespace from file path" do
        generator = described_class.new(
          repository_url: "https://github.com/user/repo",
          file_path: "  app/models/user.rb  ",
          line_number: 42,
          commit_sha: "abc123"
        )

        link = generator.generate_link

        expect(link).to eq("https://github.com/user/repo/blob/abc123/app/models/user.rb#L42")
      end
    end
  end

  describe "initialization" do
    it "accepts all required parameters" do
      generator = described_class.new(
        repository_url: "https://github.com/user/repo",
        file_path: "app/models/user.rb",
        line_number: 42,
        commit_sha: "abc123",
        branch: "develop"
      )

      expect(generator.repository_url).to eq("https://github.com/user/repo")
      expect(generator.file_path).to eq("app/models/user.rb")
      expect(generator.line_number).to eq(42)
      expect(generator.commit_sha).to eq("abc123")
      expect(generator.branch).to eq("develop")
      expect(generator.error).to be_nil
    end

    it "defaults branch to main when not provided" do
      generator = described_class.new(
        repository_url: "https://github.com/user/repo",
        file_path: "app/models/user.rb",
        line_number: 42
      )

      expect(generator.branch).to eq("main")
    end
  end

  describe "Codeberg/Gitea/Forgejo repositories" do
    it "generates link with commit SHA using /src/commit/ path" do
      generator = described_class.new(
        repository_url: "https://codeberg.org/user/repo",
        file_path: "app/models/user.rb",
        line_number: 42,
        commit_sha: "abc123def456"
      )

      link = generator.generate_link
      expect(link).to eq("https://codeberg.org/user/repo/src/commit/abc123def456/app/models/user.rb#L42")
    end

    it "generates link with branch name using /src/branch/ path" do
      generator = described_class.new(
        repository_url: "https://codeberg.org/user/repo",
        file_path: "app/models/user.rb",
        line_number: 42,
        branch: "main"
      )

      link = generator.generate_link
      expect(link).to eq("https://codeberg.org/user/repo/src/branch/main/app/models/user.rb#L42")
    end

    it "detects Gitea instances" do
      generator = described_class.new(
        repository_url: "https://gitea.mycompany.com/org/app",
        file_path: "lib/service.rb",
        line_number: 10,
        commit_sha: "deadbeef"
      )

      link = generator.generate_link
      expect(link).to include("gitea.mycompany.com/org/app/src/commit/deadbeef")
    end

    it "detects Forgejo instances" do
      generator = described_class.new(
        repository_url: "https://forgejo.example.org/team/project",
        file_path: "app/controllers/api.rb",
        line_number: 99,
        branch: "develop"
      )

      link = generator.generate_link
      expect(link).to include("forgejo.example.org/team/project/src/branch/develop")
    end
  end
end
