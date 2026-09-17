# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: the commit a checkout is on, read from .git directly
    #
    # Replaces `git rev-parse --short HEAD`. That ran in a subprocess, from the
    # capture path, once per captured error: a fork + exec in the request
    # thread, which SystemHealthSnapshot's safety rules forbid outright
    # ("no fork/subprocess ever"). Three small file reads need no git binary,
    # work in a slim container that has the .git directory but no git, and
    # cannot hang.
    #
    # Resolution order, the same one git uses:
    #   1. .git/HEAD holds a SHA (detached HEAD)
    #   2. .git/HEAD holds "ref: refs/heads/x" -> the loose ref file
    #   3. ...or the same ref in packed-refs
    # `.git` may be a FILE ("gitdir: <path>") in a worktree or submodule; a
    # worktree's refs live in the directory named by its `commondir` file.
    #
    # @example
    #   GitHeadReader.call(Rails.root) # => "39f281a" or nil
    class GitHeadReader
      SHA = /\A\h{40}(\h{24})?\z/ # SHA-1, or SHA-256 repositories
      SHORT = 7
      MAX_BYTES = 1_000_000 # packed-refs in a very large repository: skip it

      # @param root [Pathname, String, nil] the application root
      # @return [String, nil] short SHA, or nil when it cannot be determined
      def self.call(root)
        return nil if root.nil?

        git_dir = resolve_git_dir(Pathname(root.to_s).join(".git"))
        return nil unless git_dir

        head = read(git_dir.join("HEAD"))
        return nil unless head
        return head[0, SHORT] if head.match?(SHA)

        ref = head[/\Aref:\s*(\S+)\z/, 1]
        # A ref is a path under the git dir; never follow one out of it.
        return nil if ref.nil? || !ref.start_with?("refs/") || ref.include?("..")

        sha = [ git_dir, common_dir(git_dir) ].uniq.lazy.filter_map { |dir|
          loose_ref(dir, ref) || packed_ref(dir, ref)
        }.first
        sha && sha[0, SHORT]
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] GitHeadReader failed: #{e.class}: #{e.message}")
        nil
      end

      def self.resolve_git_dir(dot_git)
        return dot_git if dot_git.directory?
        return nil unless dot_git.file?

        target = read(dot_git)&.[](/\Agitdir:\s*(.+)\z/, 1)
        return nil unless target

        dir = Pathname(target)
        dir = dot_git.dirname.join(dir) unless dir.absolute?
        dir.directory? ? dir : nil
      end

      def self.common_dir(git_dir)
        relative = read(git_dir.join("commondir"))
        return git_dir unless relative

        dir = Pathname(relative)
        dir = git_dir.join(dir) unless dir.absolute?
        dir.directory? ? dir.cleanpath : git_dir
      end

      def self.loose_ref(dir, ref)
        value = read(dir.join(ref))
        value if value&.match?(SHA)
      end

      def self.packed_ref(dir, ref)
        file = dir.join("packed-refs")
        return nil unless file.file? && file.size <= MAX_BYTES

        File.foreach(file) do |line|
          sha, name = line.split(" ", 2)
          return sha if name&.strip == ref && sha.match?(SHA)
        end
        nil
      end

      # First line of a small file, stripped; nil when absent or oversized.
      def self.read(path)
        return nil unless path.file? && path.size <= MAX_BYTES

        File.open(path, &:gets)&.strip.presence
      end

      private_class_method :resolve_git_dir, :common_dir, :loose_ref, :packed_ref, :read
    end
  end
end
