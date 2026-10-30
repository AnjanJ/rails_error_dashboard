# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

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
    context "command execution error" do
      before do
        allow(reader).to receive(:git_available?).and_return(true)
        allow(Open3).to receive(:popen3).and_raise(StandardError, "Command failed")
      end

      it "handles execution errors gracefully (host-safety-0-18/REQ-3)" do
        result = nil

        expect { result = reader.read_blame }.not_to raise_error
        expect(result).to be_nil
        expect(reader.error).to match(/Git blame execution error/)
      end
    end
  end

  # Against real child processes: a fake `git` first on PATH, which answers
  # --version, records its pid and then does what each example needs.
  describe "a git that runs past COMMAND_TIMEOUT" do
    around do |example|
      Dir.mktmpdir("red_fake_git") do |dir|
        @fake_bin = dir
        path = ENV["PATH"]
        ENV["PATH"] = "#{dir}#{File::PATH_SEPARATOR}#{path}"
        begin
          example.run
        ensure
          ENV["PATH"] = path
        end
      end
    end

    before do
      stub_const("#{described_class}::COMMAND_TIMEOUT", 0.2)
      stub_const("#{described_class}::KILL_GRACE", 0.2)
    end

    def fake_git(blame)
      script = File.join(@fake_bin, "git")
      File.write(script, <<~SH)
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "git version 2.0.0"; exit 0; fi
        echo $$ > "#{@fake_bin}/git.pid"
        #{blame}
      SH
      File.chmod(0o755, script)
    end

    def recorded_pid(name)
      Integer(File.read(File.join(@fake_bin, name)))
    end

    # Every example goes through this, because the old code also ended git in
    # the end: capture3 waited out the child, however long it ran.
    def read_blame_in_time
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = reader.read_blame
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
      result
    end

    def gone?(pid)
      Process.kill(0, pid)
      false
    rescue Errno::ESRCH
      true
    end

    # A grandchild goes to init once its parent dies, and init reaps it in its
    # own time.
    def expect_gone(pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      sleep 0.01 until gone?(pid) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      expect(gone?(pid)).to be(true), "pid #{pid} is still running"
    end

    it "ends and reaps git, and reports the timeout (host-safety-0-18/REQ-1)" do
      fake_git "exec sleep 30"

      expect(read_blame_in_time).to be_nil

      expect(reader.error).to eq("Git blame timeout")
      # Not expect_gone: a child that was never reaped still answers kill(0).
      expect { Process.kill(0, recorded_pid("git.pid")) }.to raise_error(Errno::ESRCH)
    end

    it "ends a git that ignores TERM (host-safety-0-18/REQ-1)" do
      fake_git "trap '' TERM\nsleep 30"

      expect(read_blame_in_time).to be_nil

      expect(reader.error).to eq("Git blame timeout")
      expect { Process.kill(0, recorded_pid("git.pid")) }.to raise_error(Errno::ESRCH)
    end

    it "ends what git started too (host-safety-0-18/REQ-1)" do
      fake_git "sleep 30 &\necho $! > \"#{@fake_bin}/child.pid\"\nwait"

      expect(read_blame_in_time).to be_nil

      expect_gone(recorded_pid("child.pid"))
    end

    it "ends what git left holding its pipes after it exited (host-safety-0-18/REQ-1)" do
      fake_git "sleep 30 &\necho $! > \"#{@fake_bin}/child.pid\""

      expect(read_blame_in_time).to be_nil

      expect(reader.error).to eq("Git blame timeout")
      expect_gone(recorded_pid("child.pid"))
    end

    # A host's own request timeout, such as rack-timeout's, isn't a StandardError
    # and raises wherever the thread happens to be.
    it "ends git when something raises into the read, and lets it through (host-safety-0-18/REQ-1)" do
      fake_git "exec sleep 30"
      host_timeout = Class.new(Exception) # rubocop:disable Lint/InheritException
      allow(IO).to receive(:select) do
        sleep 0.01 until File.exist?(File.join(@fake_bin, "git.pid"))
        raise host_timeout
      end

      expect { reader.read_blame }.to raise_error(host_timeout)

      expect { Process.kill(0, recorded_pid("git.pid")) }.to raise_error(Errno::ESRCH)
    end

    it "treats a git that closes its pipes and keeps running as a timeout (host-safety-0-18/REQ-1)" do
      fake_git "exec >&- 2>&-\nexec sleep 30"

      expect(read_blame_in_time).to be_nil

      expect(reader.error).to eq("Git blame timeout")
      expect { Process.kill(0, recorded_pid("git.pid")) }.to raise_error(Errno::ESRCH)
    end

    it "leaves every other process alone and installs no signal handler (host-safety-0-18/REQ-4)" do
      fake_git "exec sleep 30"
      bystander = Process.spawn("sleep", "30")
      allow(Signal).to receive(:trap).and_call_original

      read_blame_in_time

      expect(Process.kill(0, bystander)).to eq(1)
      expect(Signal).not_to have_received(:trap)
    ensure
      Process.kill("KILL", bystander)
      Process.wait(bystander)
    end

    it "never interrupts the thread (host-safety-0-18/REQ-1)" do
      fake_git "exec sleep 30"
      allow(Timeout).to receive(:timeout).and_call_original

      read_blame_in_time

      expect(Timeout).not_to have_received(:timeout)
    end

    it "returns even if git can't be ended (host-safety-0-18/REQ-3)" do
      fake_git "exec sleep 30"
      allow(Process).to receive(:kill).and_call_original
      allow(Process).to receive(:kill).with("TERM", anything).and_raise(Errno::EPERM)
      allow(Process).to receive(:kill).with("KILL", anything).and_raise(Errno::EPERM)

      expect(read_blame_in_time).to be_nil

      expect(reader.error).to eq("Git blame timeout")
    ensure
      allow(Process).to receive(:kill).and_call_original
      Process.kill("KILL", recorded_pid("git.pid"))
    end

    it "signals the pid alone where there are no process groups (host-safety-0-18/REQ-4)" do
      fake_git "exec sleep 30"
      allow(Gem).to receive(:win_platform?).and_return(true)
      allow(Open3).to receive(:popen3).and_call_original
      allow(Process).to receive(:kill).and_call_original

      read_blame_in_time

      expect(Open3).to have_received(:popen3).with("git", "blame", any_args, hash_excluding(:pgroup))
      expect(Process).to have_received(:kill).with("TERM", recorded_pid("git.pid"))
    end

    it "reads both pipes at once, so a git that fills one can't stall on it (host-safety-0-18/REQ-2)" do
      stub_const("#{described_class}::COMMAND_TIMEOUT", 5)
      fake_git "head -c 200000 /dev/zero | tr '\\0' 'e' >&2\nhead -c 200000 /dev/zero | tr '\\0' 'o'\nexit 3"

      expect(read_blame_in_time).to be_nil

      expect(reader.error).to start_with("Git blame failed: eeee")
      expect(reader.error.length).to be > 200_000
    end
  end

  # What 0.17.0 returned, which came from Open3.capture3: the same bytes, the
  # same encoding, the same parsed hash.
  describe "a real blame" do
    around do |example|
      hook_env = ENV.to_h.slice("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")
      hook_env.each_key { |key| ENV.delete(key) } # set inside the pre-commit hook
      Dir.mktmpdir("red_real_blame") do |dir|
        @repo = dir
        example.run
      end
    ensure
      ENV.update(hook_env)
    end

    before do
      git = lambda do |*args, **env|
        author = { "GIT_AUTHOR_NAME" => "Zoë Müller", "GIT_AUTHOR_EMAIL" => "zoe@example.com", "GIT_AUTHOR_DATE" => "2026-01-02T03:04:05Z",
                   "GIT_COMMITTER_NAME" => "Zoë Müller", "GIT_COMMITTER_EMAIL" => "zoe@example.com", "GIT_COMMITTER_DATE" => "2026-01-02T03:04:05Z" }
        out, status = Open3.capture2e(author.merge(env), "git", "-c", "commit.gpgsign=false", *args, chdir: @repo)
        raise "git #{args.join(' ')} failed: #{out}" unless status.success?
      end
      File.write(File.join(@repo, "cafe.rb"), "# first\nPRICE = \"3 €\" # café\n")
      git.call("init", "-q")
      git.call("add", "cafe.rb")
      git.call("commit", "-q", "-m", "Add the café")
      allow(Rails).to receive(:root).and_return(Pathname.new(@repo))
    end

    let(:real_reader) { described_class.new(File.join(@repo, "cafe.rb"), 2) }

    it "returns what capture3 and the parser gave, non-ASCII included (host-safety-0-18/REQ-2)" do
      stdout, = Open3.capture3("git", "blame", "-L", "2,2", "--porcelain", "--", File.join(@repo, "cafe.rb"), chdir: @repo)
      expected = real_reader.send(:parse_blame_output, stdout)

      result = real_reader.read_blame

      expect(result).to eq(expected)
      expect(result[:author]).to eq("Zoë Müller")
      expect(result[:author].encoding).to eq(Encoding::UTF_8)
      expect(result[:line]).to eq("PRICE = \"3 €\" # café")
    end

    it "keeps the error text when git refuses (host-safety-0-18/REQ-2)" do
      outside = described_class.new(File.join(@repo, "cafe.rb"), 999)

      expect(outside.read_blame).to be_nil

      expect(outside.error).to start_with("Git blame failed: fatal:")
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
