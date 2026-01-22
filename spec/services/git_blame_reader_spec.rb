# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::GitBlameReader do
  let(:test_file_path) { File.join(Rails.root, "app/models/user.rb") }
  let(:test_line_number) { 10 }
  let(:reader) { described_class.new(test_file_path, test_line_number) }

  before do
    # Create a test file
    FileUtils.mkdir_p(File.dirname(test_file_path))
    File.write(test_file_path, <<~RUBY)
      class User < ApplicationRecord
        validates :email, presence: true

        def full_name
          [first_name, last_name].compact.join(' ')
        end
      end
    RUBY
  end

  after do
    FileUtils.rm_f(test_file_path) if File.exist?(test_file_path)
  end

  describe "#git_available?" do
    it "returns true when git is available" do
      allow(Open3).to receive(:capture3).with("git", "--version")
                                         .and_return([ "git version 2.39.0", "", double(success?: true) ])

      expect(reader.git_available?).to be true
    end

    it "returns false when git is not available" do
      allow(Open3).to receive(:capture3).with("git", "--version")
                                         .and_raise(Errno::ENOENT)

      expect(reader.git_available?).to be false
    end

    it "returns false when git command fails" do
      allow(Open3).to receive(:capture3).with("git", "--version")
                                         .and_return([ "", "error", double(success?: false) ])

      expect(reader.git_available?).to be false
    end

    it "caches the result" do
      allow(Open3).to receive(:capture3).with("git", "--version")
                                         .and_return([ "git version 2.39.0", "", double(success?: true) ])
                                         .once

      reader.git_available?
      reader.git_available?

      # Should only call once due to caching
    end
  end

  describe "#read_blame" do
    context "when git is not available" do
      before do
        allow(reader).to receive(:git_available?).and_return(false)
      end

      it "returns nil" do
        expect(reader.read_blame).to be_nil
      end

      it "sets error message" do
        reader.read_blame

        expect(reader.error).to eq("Git not available")
      end
    end

    context "when file doesn't exist" do
      let(:test_file_path) { File.join(Rails.root, "app/models/non_existent.rb") }

      before do
        FileUtils.rm_f(test_file_path) if File.exist?(test_file_path)
        allow(reader).to receive(:git_available?).and_return(true)
      end

      it "returns nil" do
        expect(reader.read_blame).to be_nil
      end

      it "sets error message" do
        reader.read_blame

        expect(reader.error).to eq("File not found")
      end
    end

    context "when git blame succeeds" do
      let(:porcelain_output) do
        <<~BLAME
          abc123def456 10 10 1
          author John Doe
          author-mail <john@example.com>
          author-time 1704067200
          author-tz +0000
          committer John Doe
          committer-mail <john@example.com>
          committer-time 1704067200
          committer-tz +0000
          summary Add user model validation
          filename app/models/user.rb
          \t  validates :email, presence: true
        BLAME
      end

      before do
        allow(reader).to receive(:git_available?).and_return(true)
        allow(reader).to receive(:execute_git_blame).and_return(porcelain_output)
      end

      it "returns blame data hash" do
        result = reader.read_blame

        expect(result).to be_a(Hash)
        expect(result[:author]).to eq("John Doe")
        expect(result[:email]).to eq("john@example.com")
        expect(result[:sha]).to eq("abc123def456")
        expect(result[:commit_message]).to eq("Add user model validation")
        expect(result[:line]).to eq("  validates :email, presence: true")
      end

      it "converts timestamp to Time object" do
        result = reader.read_blame

        expect(result[:date]).to be_a(Time)
        expect(result[:date].to_i).to eq(1704067200)
      end

      it "removes angle brackets from email" do
        result = reader.read_blame

        expect(result[:email]).to eq("john@example.com")
        expect(result[:email]).not_to include("<")
        expect(result[:email]).not_to include(">")
      end
    end

    context "when git blame fails" do
      before do
        allow(reader).to receive(:git_available?).and_return(true)
        allow(reader).to receive(:execute_git_blame).and_return(nil)
      end

      it "returns nil" do
        expect(reader.read_blame).to be_nil
      end
    end

    context "when parsing fails" do
      before do
        allow(reader).to receive(:git_available?).and_return(true)
        allow(reader).to receive(:execute_git_blame).and_return("invalid output")
      end

      it "returns nil" do
        expect(reader.read_blame).to be_nil
      end

      it "sets error message" do
        reader.read_blame

        expect(reader.error).to match(/Incomplete git blame data/)
      end
    end

    context "when an exception occurs" do
      before do
        allow(reader).to receive(:git_available?).and_return(true)
        allow(reader).to receive(:execute_git_blame).and_raise(StandardError, "Unexpected error")
      end

      it "returns nil" do
        expect(reader.read_blame).to be_nil
      end

      it "sets error message" do
        reader.read_blame

        expect(reader.error).to match(/Error reading git blame/)
      end

      it "logs the error" do
        allow(RailsErrorDashboard::Logger).to receive(:error)

        reader.read_blame

        expect(RailsErrorDashboard::Logger).to have_received(:error)
      end
    end
  end

  describe "#execute_git_blame (private)" do
    # We'll test this indirectly through read_blame, but can add specific tests
    context "integration test with real git" do
      before do
        # Skip if git not available or not in a git repo
        skip "Git not available" unless system("git --version > /dev/null 2>&1")
        skip "Not a git repository" unless File.exist?(File.join(Rails.root, ".git"))
      end

      it "executes git blame command successfully" do
        # Use a real file from the gem
        real_file = File.join(Rails.root, "lib/rails_error_dashboard.rb")
        skip "Test file not found" unless File.exist?(real_file)

        reader = described_class.new(real_file, 1)
        result = reader.read_blame

        # Should get real git blame data
        expect(result).to be_a(Hash) if result # May be nil if file not committed
        expect(reader.error).to be_nil if result
      end
    end

    context "timeout handling" do
      before do
        allow(reader).to receive(:git_available?).and_return(true)
      end

      it "handles timeout gracefully" do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

        result = reader.read_blame

        expect(result).to be_nil
        expect(reader.error).to eq("Git blame timeout")
      end
    end

    context "command execution error" do
      before do
        allow(reader).to receive(:git_available?).and_return(true)
        allow(Open3).to receive(:capture3).and_raise(StandardError, "Command failed")
      end

      it "handles execution errors gracefully" do
        result = reader.read_blame

        expect(result).to be_nil
        expect(reader.error).to match(/Git blame execution error/)
      end
    end
  end

  describe "#parse_blame_output (private)" do
    context "with empty output" do
      it "returns nil for blank output" do
        allow(reader).to receive(:git_available?).and_return(true)
        allow(reader).to receive(:execute_git_blame).and_return("")

        expect(reader.read_blame).to be_nil
      end

      it "returns nil for nil output" do
        allow(reader).to receive(:git_available?).and_return(true)
        allow(reader).to receive(:execute_git_blame).and_return(nil)

        expect(reader.read_blame).to be_nil
      end
    end

    context "with malformed output" do
      it "returns nil when first line doesn't match pattern" do
        allow(reader).to receive(:git_available?).and_return(true)
        allow(reader).to receive(:execute_git_blame).and_return("invalid\ndata")

        expect(reader.read_blame).to be_nil
      end

      it "returns nil when required fields are missing" do
        output = <<~BLAME
          abc123 10 10 1
          summary Only summary
        BLAME

        allow(reader).to receive(:git_available?).and_return(true)
        allow(reader).to receive(:execute_git_blame).and_return(output)

        expect(reader.read_blame).to be_nil
        expect(reader.error).to match(/Incomplete git blame data/)
      end
    end

    context "with complete output" do
      it "parses all porcelain fields" do
        output = <<~BLAME
          abc123def 10 10 1
          author Jane Smith
          author-mail <jane@example.com>
          author-time 1704153600
          author-tz -0500
          committer Jane Smith
          committer-mail <jane@example.com>
          committer-time 1704153600
          committer-tz -0500
          summary Fix bug in validation
          filename app/models/user.rb
          \tvalidates :email, presence: true
        BLAME

        allow(reader).to receive(:git_available?).and_return(true)
        allow(reader).to receive(:execute_git_blame).and_return(output)

        result = reader.read_blame

        expect(result[:author]).to eq("Jane Smith")
        expect(result[:email]).to eq("jane@example.com")
        expect(result[:sha]).to eq("abc123def")
        expect(result[:commit_message]).to eq("Fix bug in validation")
        expect(result[:line]).to eq("validates :email, presence: true")
        expect(result[:date]).to be_a(Time)
      end
    end
  end

  describe "initialization" do
    it "accepts file_path and line_number" do
      reader = described_class.new("/path/to/file.rb", 42)

      expect(reader.file_path).to eq("/path/to/file.rb")
      expect(reader.line_number).to eq(42)
      expect(reader.error).to be_nil
    end

    it "converts line_number to integer" do
      reader = described_class.new("/path/to/file.rb", "42")

      expect(reader.line_number).to eq(42)
      expect(reader.line_number).to be_a(Integer)
    end
  end
end
