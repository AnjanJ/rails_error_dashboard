# frozen_string_literal: true

require "spec_helper"
require "rdoc"

# Guards how rubygems.org renders this gem's description.
#
# WHY THIS EXISTS: the gem page showed one cramped wall of text with an
# unclickable demo link for months, and more than one attempt to fix it failed
# silently — the gemspec looked formatted in the editor while the published page
# was unchanged, because nothing here could tell the difference.
#
# rubygems.org's RubygemsHelper#simple_markup does exactly this:
#
#     if /^==+ [A-Z]/.match?(text)
#       sanitize RDoc::Markup.new.convert(text, RDoc::Markup::ToHtml.new(pipe: true))
#     else
#       tag.p(escape_once(sanitize(text.strip)))
#     end
#
# So the whole outcome hinges on one anchored regexp. These examples reproduce
# that gate and the RDoc conversion rather than asserting on the source text,
# because "the gemspec contains == headings" was true of the broken version too.
RSpec.describe "gemspec description rendering on rubygems.org" do
  # The published gate, copied verbatim from rubygems.org.
  RUBYGEMS_RDOC_GATE = /^==+ [A-Z]/

  let(:spec) do
    Gem::Specification.load(File.expand_path("../rails_error_dashboard.gemspec", __dir__))
  end

  let(:description) { spec.description }

  let(:rendered) do
    RDoc::Markup.new.convert(description, RDoc::Markup::ToHtml.new(pipe: true))
  end

  it "loads the gemspec" do
    expect(spec).to be_a(Gem::Specification)
    expect(description).not_to be_empty
  end

  describe "the RDoc gate" do
    it "matches, so the page renders as RDoc rather than a single paragraph" do
      expect(description).to match(RUBYGEMS_RDOC_GATE)
    end

    # The regexp is anchored at ^, so a heading indented by even one space is
    # invisible to it. This is the exact defect that made a previous fix a no-op:
    # <<~HEREDOC strips only the COMMON indentation, so a body indented past its
    # terminator keeps leading spaces on every line.
    it "starts its headings at column 0" do
      heading_lines = description.lines.grep(/^\s*==+ /)

      expect(heading_lines).not_to be_empty
      heading_lines.each do |line|
        expect(line).to start_with("=="),
          "heading is indented, which defeats /^==+ [A-Z]/: #{line.inspect}"
      end
    end

    it "would not render as one cramped paragraph" do
      # The else-branch of simple_markup: everything in a single <p>.
      expect(rendered.scan(/<p>/).size).to be > 1
    end
  end

  describe "the rendered HTML" do
    it "has section headings" do
      expect(rendered.scan(/<h\d/).size).to be >= 3
    end

    it "has a bullet list" do
      expect(rendered.scan(/<li>/).size).to be >= 3
    end

    # The reported symptom: "the live demo link is not clickable at all".
    it "renders the live demo URL as a real anchor" do
      expect(rendered).to include('<a href="https://rails-error-dashboard.anjan.dev">')
    end

    it "renders the documentation URL as a real anchor" do
      expect(rendered).to match(%r{<a href="https://AnjanJ\.github\.io/rails_error_dashboard"})
    end
  end

  describe "the summary" do
    # RubyGems warns above 255 and the value is truncated in listings.
    it "stays within the length RubyGems displays" do
      expect(spec.summary.length).to be <= 255
    end

    it "is a single line" do
      expect(spec.summary).not_to include("\n")
    end
  end
end
