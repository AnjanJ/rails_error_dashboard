# frozen_string_literal: true

require "rails_helper"

# What the docs say RED is and runs on, as 1.0.0.rc1 freezes it.
# release-1-0-rc1/REQ-20: no page calls RED beta, and the README and the FAQ
# state the floors decision 0003 set (Rails 7.2 to 8.1, Ruby 3.3 to 4.0).
# release-1-0-rc1/REQ-21: the customization guide shows only options the
# code has.
RSpec.describe "What the docs say about RED's status and floors" do
  root = RailsErrorDashboard::Engine.root

  # The pages a reader sees: the README, the site's index, docs/ and the
  # site's copies of it.
  pages = [ "README.md", "index.md" ] +
    Dir.chdir(root) { Dir["docs/**/*.md"] + Dir["_{getting_started,reference,guides,features}/**/*.md"] }.sort

  # "beta" that isn't about RED: a sample version string, and the translations
  # guide explaining why it doesn't use the word.
  not_about_red = [ /"2\.1-beta"/, /described as "beta"/ ]

  it "has pages to check" do
    expect(pages.size).to be > 20
  end

  it "calls RED beta nowhere (release-1-0-rc1/REQ-20)" do
    calling = pages.flat_map do |page|
      root.join(page).readlines.each_with_index
        .select { |line, _| line.match?(/\bbeta\b/i) && not_about_red.none? { |ok| line.match?(ok) } }
        .map { |line, index| "#{page}:#{index + 1}: #{line.strip[0, 100]}" }
    end

    expect(calling).to eq([])
  end

  %w[README.md docs/FAQ.md _reference/faq.md].each do |page|
    it "#{page} states Rails 7.2 to 8.1 and Ruby 3.3 to 4.0 (release-1-0-rc1/REQ-20)" do
      text = root.join(page).read

      expect(text).to match(/Rails 7\.2\s*(?:–|-|to)\s*8\.1/)
      expect(text).to match(/Ruby 3\.3\s*(?:–|-|to)\s*4\.0/)
    end

    it "#{page} names no Rails or Ruby below the floors (release-1-0-rc1/REQ-20)" do
      below = root.join(page).readlines.each_with_index
        .select { |line, _| line.match?(/Rails 7\.[01]\b|Ruby 3\.[0-2]\b|Rails >= ?7\.[01]\b|Ruby >= ?3\.[0-2]\b/) }
        .map { |line, index| "#{page}:#{index + 1}: #{line.strip[0, 100]}" }

      expect(below).to eq([])
    end
  end

  # Rails' own settings, written in the host's config/application.rb.
  rails_settings = %w[assets middleware]
  options = RailsErrorDashboard::Configuration.public_instance_methods.map(&:to_s)

  %w[docs/CUSTOMIZATION.md _guides/customization.md].each do |page|
    it "#{page} shows only configuration options RED has (release-1-0-rc1/REQ-21)" do
      named = root.join(page).read.scan(/(?<![\w.])config\.([a-z_]+)/).flatten.uniq - rails_settings
      missing = named.reject { |name| options.include?(name) || options.include?("#{name}=") }

      expect(missing).to eq([])
    end
  end
end
