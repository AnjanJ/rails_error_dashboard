# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::BacktraceProcessor do
  describe ".truncate" do
    it "returns nil for nil backtrace" do
      expect(described_class.truncate(nil)).to be_nil
    end

    it "returns empty string for empty backtrace" do
      expect(described_class.truncate([])).to eq("")
    end

    it "returns full backtrace when under limit" do
      backtrace = 5.times.map { |i| "line_#{i}.rb:#{i}" }
      result = described_class.truncate(backtrace, max_lines: 10)

      expect(result.lines.count).to eq(5)
      expect(result).not_to include("truncated")
    end

    it "truncates backtrace when over limit" do
      backtrace = 20.times.map { |i| "line_#{i}.rb:#{i}" }
      result = described_class.truncate(backtrace, max_lines: 10)

      expect(result.lines.count).to eq(11) # 10 lines + truncation notice
      expect(result).to include("... (10 more lines truncated)")
    end

    it "preserves first N lines" do
      backtrace = 20.times.map { |i| "line_#{i}.rb:#{i}" }
      result = described_class.truncate(backtrace, max_lines: 5)

      expect(result).to include("line_0.rb:0")
      expect(result).to include("line_4.rb:4")
      expect(result).not_to include("line_5.rb:5")
    end

    it "handles exact limit without truncation notice" do
      backtrace = 10.times.map { |i| "line_#{i}.rb:#{i}" }
      result = described_class.truncate(backtrace, max_lines: 10)

      expect(result.lines.count).to eq(10)
      expect(result).not_to include("truncated")
    end

    it "handles max_lines of 0" do
      backtrace = 5.times.map { |i| "line_#{i}.rb:#{i}" }
      result = described_class.truncate(backtrace, max_lines: 0)

      expect(result).to eq("... (5 more lines truncated)")
    end

    it "uses configured max_backtrace_lines when not specified" do
      RailsErrorDashboard.configuration.max_backtrace_lines = 3
      backtrace = 10.times.map { |i| "line_#{i}.rb:#{i}" }

      result = described_class.truncate(backtrace)

      expect(result.lines.count).to eq(4) # 3 + truncation notice
      expect(result).to include("... (7 more lines truncated)")
    ensure
      RailsErrorDashboard.reset_configuration!
    end
  end

  describe ".calculate_signature" do
    it "returns nil for nil backtrace" do
      expect(described_class.calculate_signature(nil)).to be_nil
    end

    it "returns nil for empty string" do
      expect(described_class.calculate_signature("")).to be_nil
    end

    it "returns nil for backtrace with no .rb files" do
      expect(described_class.calculate_signature("no ruby files here")).to be_nil
    end

    it "returns a 16-character hex string" do
      backtrace = "app/models/user.rb:10:in `save'\napp/controllers/users_controller.rb:20:in `create'"
      result = described_class.calculate_signature(backtrace)

      expect(result).to be_a(String)
      expect(result.length).to eq(16)
      expect(result).to match(/\A[0-9a-f]+\z/)
    end

    it "accepts backtrace as array" do
      backtrace = [
        "app/models/user.rb:10:in `save'",
        "app/controllers/users_controller.rb:20:in `create'"
      ]
      result = described_class.calculate_signature(backtrace)

      expect(result).to be_a(String)
      expect(result.length).to eq(16)
    end

    it "accepts backtrace as string" do
      backtrace = "app/models/user.rb:10:in `save'\napp/controllers/users_controller.rb:20:in `create'"
      result = described_class.calculate_signature(backtrace)

      expect(result).to be_a(String)
      expect(result.length).to eq(16)
    end

    it "produces same signature regardless of line numbers" do
      bt1 = "app/models/user.rb:10:in `save'"
      bt2 = "app/models/user.rb:99:in `save'"

      expect(described_class.calculate_signature(bt1)).to eq(described_class.calculate_signature(bt2))
    end

    it "produces different signatures for different files" do
      bt1 = "app/models/user.rb:10:in `save'"
      bt2 = "app/models/post.rb:10:in `save'"

      expect(described_class.calculate_signature(bt1)).not_to eq(described_class.calculate_signature(bt2))
    end

    it "is order-independent (sorted file paths)" do
      bt1 = "app/models/user.rb:10:in `save'\napp/models/post.rb:5:in `update'"
      bt2 = "app/models/post.rb:5:in `update'\napp/models/user.rb:10:in `save'"

      expect(described_class.calculate_signature(bt1)).to eq(described_class.calculate_signature(bt2))
    end

    it "only uses first 20 lines" do
      lines = 25.times.map { |i| "app/models/model_#{i}.rb:#{i}:in `method_#{i}'" }
      bt_25 = lines.join("\n")
      bt_20 = lines.first(20).join("\n")

      expect(described_class.calculate_signature(bt_25)).to eq(described_class.calculate_signature(bt_20))
    end
  end
end
