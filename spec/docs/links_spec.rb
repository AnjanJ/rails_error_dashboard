# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-0/REQ-17: dead anchors and a link to a page that isn't
# there survived every docs pass, because nothing followed the links. Every
# relative link and #anchor in the docs and their Jekyll copies must resolve.
RSpec.describe "Documentation links" do
  root = RailsErrorDashboard::Engine.root

  # The Jekyll site serves these collections (see _config.yml) under
  # /rails_error_dashboard
  site_collections = {
    "docs/guides/" => "_guides",
    "docs/features/" => "_features",
    "docs/reference/" => "_reference",
    "docs/" => "_getting_started"
  }

  files = Dir.glob(root.join("{docs/**/*.md,_guides/*.md,_features/*.md,_getting_started/*.md,_reference/*.md,README.md}"))

  # Markdown lines outside fenced code blocks
  prose = lambda do |path|
    fenced = false
    File.readlines(path).reject do |line|
      fenced = !fenced if line.lstrip.start_with?("```")
      fenced || line.lstrip.start_with?("```")
    end
  end

  # Heading ids as GitHub renders docs/ and kramdown renders the site, plus
  # explicit ids
  anchors = Hash.new do |cache, path|
    ids = []
    prose.call(path).each do |line|
      if (heading = line[/\A\#{1,6}\s+(.+?)\s*#*\s*\z/, 1])
        text = heading.downcase.gsub(/<[^>]+>/, "").delete("`").gsub(/\[([^\]]*)\]\([^)]*\)/, '\1')
        github = text.gsub(/[^\p{Word}\- ]/u, "").tr(" ", "-")
        ids << github << github.sub(/\A[^a-z]+/, "")
      end
      line.scan(/(?:id|name)=["']([^"']+)["']/) { |(id)| ids << id }
      line.scan(/\{:?\s*#([\w-]+)\s*\}/) { |(id)| ids << id }
    end
    # GitHub numbers repeated headings: second "foo" is "foo-1"
    cache[path] = ids.tally.flat_map { |id, count| [ id ] + (1...count).map { |n| "#{id}-#{n}" } }.to_set
  end

  resolve = lambda do |from, target|
    if target.start_with?("/rails_error_dashboard/")
      site_path = target.delete_prefix("/rails_error_dashboard/").chomp("/")
      prefix, dir = site_collections.find { |p, _| site_path.start_with?(p) && !site_path.delete_prefix(p).include?("/") }
      # Anything else (docs/images/…) is a static file served from the repo
      return root.join(site_path).to_s unless prefix

      root.join(dir, "#{site_path.delete_prefix(prefix)}.md").to_s
    elsif target.start_with?("/")
      nil
    else
      File.expand_path(target, File.dirname(from))
    end
  end

  it "resolves every relative link and anchor" do
    broken = []

    files.each do |file|
      prose.call(file).join.scan(/(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)|!\[[^\]]*\]\(([^)\s]+)\)/) do |link, image|
        target = link || image
        next if target.match?(%r{\A(?:[a-z]+:|//|\{\{)}) # absolute URLs, mailto:, Liquid

        path, anchor = target.split("#", 2)
        dest = path.empty? ? file : resolve.call(file, path)
        relative = file.delete_prefix("#{root}/")

        if dest.nil? || !File.exist?(dest)
          broken << "#{relative}: #{target} (no such page)"
        elsif anchor.present? && dest.end_with?(".md") && !anchors[dest].include?(anchor)
          broken << "#{relative}: #{target} (no such anchor)"
        end
      end
    end

    expect(broken).to be_empty, "broken links:\n  #{broken.uniq.join("\n  ")}"
  end
end
