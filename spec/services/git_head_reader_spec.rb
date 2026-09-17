# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe RailsErrorDashboard::Services::GitHeadReader do
  let(:sha) { "0123456789abcdef0123456789abcdef01234567" }

  around do |example|
    Dir.mktmpdir("red-git-head") do |dir|
      @root = Pathname(dir)
      example.run
    end
  end

  def write(path, content)
    file = @root.join(path)
    FileUtils.mkdir_p(file.dirname)
    File.write(file, content)
  end

  it "reads a detached HEAD" do
    write(".git/HEAD", "#{sha}\n")

    expect(described_class.call(@root)).to eq("0123456")
  end

  it "follows a symbolic ref to its loose ref file" do
    write(".git/HEAD", "ref: refs/heads/main\n")
    write(".git/refs/heads/main", "#{sha}\n")

    expect(described_class.call(@root)).to eq("0123456")
  end

  it "falls back to packed-refs when the loose ref is gone" do
    write(".git/HEAD", "ref: refs/heads/release/1.0\n")
    write(".git/packed-refs", "# pack-refs with: peeled fully-peeled sorted\n" \
                              "ffffffffffffffffffffffffffffffffffffffff refs/heads/main\n" \
                              "#{sha} refs/heads/release/1.0\n^aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n")

    expect(described_class.call(@root)).to eq("0123456")
  end

  it "follows a .git FILE (worktree / submodule) to the real git dir, and its commondir" do
    write("real/worktrees/wt/HEAD", "ref: refs/heads/feature\n")
    write("real/worktrees/wt/commondir", "../..\n")
    write("real/refs/heads/feature", "#{sha}\n")
    write("checkout/.git", "gitdir: #{@root.join('real/worktrees/wt')}\n")

    expect(described_class.call(@root.join("checkout"))).to eq("0123456")
  end

  it "returns nil without a repository" do
    expect(described_class.call(@root)).to be_nil
  end

  it "returns nil for an unborn branch, garbage, or a ref that escapes the git dir" do
    write(".git/HEAD", "ref: refs/heads/main\n")
    expect(described_class.call(@root)).to be_nil

    write(".git/HEAD", "not a sha\n")
    expect(described_class.call(@root)).to be_nil

    write("secret", "#{sha}\n")
    write(".git/HEAD", "ref: ../secret\n")
    expect(described_class.call(@root)).to be_nil
  end

  it "never raises and never spawns a subprocess" do
    expect(described_class).not_to receive(:`)
    expect(Kernel).not_to receive(:system)

    expect { described_class.call(nil) }.not_to raise_error
    expect { described_class.call("/definitely/not/here") }.not_to raise_error
  end

  it "agrees with git itself for this repository" do
    expected = `git -C #{RailsErrorDashboard::Engine.root} rev-parse HEAD 2>/dev/null`.strip
    skip "not a git checkout" if expected.empty?

    expect(described_class.call(RailsErrorDashboard::Engine.root)).to eq(expected[0, 7])
  end
end
