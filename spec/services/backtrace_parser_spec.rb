# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::BacktraceParser do
  describe ".parse" do
    it "parses standard backtrace lines" do
      backtrace = "/app/models/user.rb:10:in `save'\n/app/controllers/users_controller.rb:20:in `create'"
      result = described_class.parse(backtrace)

      expect(result.length).to eq(2)
      expect(result.first[:file_path]).to eq("/app/models/user.rb")
      expect(result.first[:line_number]).to eq(10)
      expect(result.first[:method_name]).to eq("save")
    end

    it "returns empty array for blank input" do
      expect(described_class.parse(nil)).to eq([])
      expect(described_class.parse("")).to eq([])
    end

    it "categorizes app frames correctly" do
      backtrace = "/my_app/app/models/user.rb:10:in `save'"
      result = described_class.parse(backtrace)
      expect(result.first[:category]).to eq(:app)
    end

    it "categorizes gem frames correctly" do
      backtrace = "/usr/local/lib/ruby/gems/3.2.0/gems/activerecord-7.0.0/lib/active_record/base.rb:10:in `find'"
      result = described_class.parse(backtrace)
      expect(result.first[:category]).to eq(:gem)
    end
  end

  describe ".from_locations" do
    # Use caller_locations to get real Location objects
    def capture_locations
      caller_locations(1, 10)
    end

    it "converts Location objects to frame hashes" do
      locations = capture_locations
      result = described_class.from_locations(locations)

      expect(result).to be_an(Array)
      expect(result).not_to be_empty

      frame = result.first
      expect(frame).to have_key(:index)
      expect(frame).to have_key(:file_path)
      expect(frame).to have_key(:line_number)
      expect(frame).to have_key(:method_name)
      expect(frame).to have_key(:category)
      expect(frame).to have_key(:full_line)
      expect(frame).to have_key(:short_path)
    end

    it "extracts file path from Location objects" do
      locations = capture_locations
      result = described_class.from_locations(locations)

      frame = result.first
      # Should contain this spec file path
      expect(frame[:file_path]).to include("backtrace_parser_spec.rb")
    end

    it "extracts line number as integer" do
      locations = capture_locations
      result = described_class.from_locations(locations)

      expect(result.first[:line_number]).to be_a(Integer)
      expect(result.first[:line_number]).to be > 0
    end

    it "extracts method name from label" do
      locations = capture_locations
      result = described_class.from_locations(locations)

      expect(result.first[:method_name]).to be_a(String)
      expect(result.first[:method_name]).not_to be_empty
    end

    it "uses absolute_path when available" do
      locations = capture_locations
      result = described_class.from_locations(locations)

      # absolute_path should be an absolute path
      frame = result.first
      expect(frame[:file_path]).to start_with("/")
    end

    it "categorizes frames correctly" do
      locations = capture_locations
      result = described_class.from_locations(locations)

      # Categories should be valid symbols
      valid_categories = [ :app, :gem, :framework, :ruby_core ]
      result.each do |frame|
        expect(valid_categories).to include(frame[:category])
      end
    end

    it "returns empty array for nil input" do
      expect(described_class.from_locations(nil)).to eq([])
    end

    it "returns empty array for empty input" do
      expect(described_class.from_locations([])).to eq([])
    end

    it "produces same hash structure as .parse" do
      locations = capture_locations
      location_result = described_class.from_locations(locations)

      # Reconstruct a backtrace string from the locations
      backtrace_string = locations.map(&:to_s).join("\n")
      parse_result = described_class.parse(backtrace_string)

      # Both should have the same keys
      location_keys = location_result.first.keys.sort
      parse_keys = parse_result.first.keys.sort
      expect(location_keys).to eq(parse_keys)
    end

    it "sets sequential index values" do
      locations = capture_locations
      result = described_class.from_locations(locations)

      result.each_with_index do |frame, i|
        expect(frame[:index]).to eq(i)
      end
    end

    it "generates full_line in standard backtrace format" do
      locations = capture_locations
      result = described_class.from_locations(locations)

      frame = result.first
      # full_line should look like: /path/to/file.rb:123:in `method_name' or 'method_name'
      expect(frame[:full_line]).to match(%r{.+:\d+:in [`'].+['`]})
    end
  end
end
