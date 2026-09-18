# frozen_string_literal: true

require "rails_helper"

# JSON inlined into a <script> block has to go through js_safe_json. Plain
# #to_json is only safe while ActiveSupport.escape_html_entities_in_json is
# true, which is a host-app setting the gem does not own: with it off, a value
# containing "</script>" closes the block and the rest is parsed as HTML.
RSpec.describe "JSON embedded in views" do
  it "is never emitted with raw ... to_json or to_json.html_safe" do
    root = RailsErrorDashboard::Engine.root
    # Matched against the whole file, inside one ERB tag: one of the original
    # sites was a multi-line block ending in "}.to_json %>", which no
    # line-by-line search could see.
    unsafe = /<%=\s*raw\b(?:(?!%>).)*?\.to_json|\.to_json\s*\)?\.html_safe/m

    offenders = Dir[root.join("app/views/**/*.erb")].sort.flat_map do |file|
      source = File.read(file)
      source.to_enum(:scan, unsafe).map do
        line = source[0, Regexp.last_match.begin(0)].count("\n") + 1
        "#{Pathname(file).relative_path_from(root)}:#{line}"
      end
    end

    expect(offenders).to eq([])
  end
end
