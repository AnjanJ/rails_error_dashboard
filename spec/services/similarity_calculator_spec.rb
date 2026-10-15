# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::SimilarityCalculator do
  describe ".call" do
    let(:error1) { create(:error_log, :with_backtrace, platform: "iOS") }
    let(:error2) { create(:error_log, :with_backtrace, platform: "iOS") }

    it "returns 1.0 for the same error" do
      score = described_class.call(error1, error1)
      expect(score).to eq(1.0)
    end

    it "returns 0.0 for errors on different platforms" do
      error1.update(platform: "iOS")
      error2.update(platform: "Android")

      score = described_class.call(error1, error2)
      expect(score).to eq(0.0)
    end

    it "calculates similarity based on backtrace and message" do
      # Similar backtraces and messages
      error1.update(
        backtrace: "app/models/user.rb:10:in `save'\napp/controllers/users_controller.rb:20:in `create'",
        message: "undefined method 'name' for nil:NilClass"
      )
      error2.update(
        backtrace: "app/models/user.rb:10:in `save'\napp/controllers/users_controller.rb:20:in `create'",
        message: "undefined method 'email' for nil:NilClass"
      )

      score = described_class.call(error1, error2)
      expect(score).to be_between(0.6, 1.0)
    end

    it "returns high similarity for identical backtraces with different messages" do
      error1.update(
        backtrace: "app/models/user.rb:10:in `save'\napp/models/user.rb:15:in `validate'",
        message: "Validation failed: Name can't be blank"
      )
      error2.update(
        backtrace: "app/models/user.rb:10:in `save'\napp/models/user.rb:15:in `validate'",
        message: "Validation failed: Email can't be blank"
      )

      score = described_class.call(error1, error2)
      expect(score).to be > 0.7 # High backtrace similarity (70% weight)
    end

    it "returns low similarity for different backtraces with similar messages" do
      error1.update(
        backtrace: "app/models/user.rb:10:in `save'",
        message: "undefined method 'name' for nil:NilClass"
      )
      error2.update(
        backtrace: "app/controllers/posts_controller.rb:5:in `create'",
        message: "undefined method 'title' for nil:NilClass"
      )

      score = described_class.call(error1, error2)
      expect(score).to be < 0.5 # Different backtraces dominate
    end
  end

  describe "#calculate_backtrace_similarity" do
    it "returns 0.0 for empty backtraces" do
      error1 = create(:error_log, backtrace: nil)
      error2 = create(:error_log, backtrace: "some backtrace")

      calculator = described_class.new(error1, error2)
      expect(calculator.send(:calculate_backtrace_similarity)).to eq(0.0)
    end

    it "returns 1.0 for identical backtraces" do
      backtrace = "app/models/user.rb:10:in `save'\napp/controllers/users_controller.rb:20:in `create'"
      error1 = create(:error_log, backtrace: backtrace)
      error2 = create(:error_log, backtrace: backtrace)

      calculator = described_class.new(error1, error2)
      expect(calculator.send(:calculate_backtrace_similarity)).to eq(1.0)
    end

    it "uses Jaccard similarity on frames" do
      error1 = create(:error_log, backtrace: "app/models/user.rb:10:in `save'\napp/models/user.rb:15:in `validate'")
      error2 = create(:error_log, backtrace: "app/models/user.rb:10:in `save'\napp/controllers/users_controller.rb:20:in `create'")

      calculator = described_class.new(error1, error2)
      similarity = calculator.send(:calculate_backtrace_similarity)

      # Intersection: 1 frame (user.rb:save)
      # Union: 3 frames (user.rb:save, user.rb:validate, users_controller.rb:create)
      # Jaccard = 1/3 = 0.333...
      expect(similarity).to be_within(0.01).of(0.33)
    end
  end

  describe "#calculate_message_similarity" do
    it "returns 1.0 for identical messages" do
      error1 = create(:error_log, message: "undefined method 'name' for nil:NilClass")
      error2 = create(:error_log, message: "undefined method 'name' for nil:NilClass")

      calculator = described_class.new(error1, error2)
      expect(calculator.send(:calculate_message_similarity)).to eq(1.0)
    end

    it "returns 0.0 for empty messages" do
      error1 = build(:error_log, message: "")
      error1.save(validate: false) # Skip validation to allow empty message
      error2 = create(:error_log, message: "some message")

      calculator = described_class.new(error1, error2)
      expect(calculator.send(:calculate_message_similarity)).to eq(0.0)
    end

    it "normalizes messages before comparison" do
      error1 = create(:error_log, message: "User ID 123 not found")
      error2 = create(:error_log, message: "User ID 456 not found")

      calculator = described_class.new(error1, error2)
      similarity = calculator.send(:calculate_message_similarity)

      # After normalization: "user id N not found" (identical)
      expect(similarity).to be > 0.9
    end

    it "uses Levenshtein distance" do
      error1 = create(:error_log, message: "undefined method on User")
      error2 = create(:error_log, message: "undefined method on Account")

      calculator = described_class.new(error1, error2)
      similarity = calculator.send(:calculate_message_similarity)

      # Similar but not identical (User vs Account)
      expect(similarity).to be_between(0.7, 0.95)
    end
  end

  describe "#extract_frames" do
    it "extracts file paths and method names from backtrace" do
      backtrace = "app/models/user.rb:10:in `save'\napp/controllers/users_controller.rb:20:in `create'"
      error = create(:error_log, backtrace: backtrace)

      calculator = described_class.new(error, error)
      frames = calculator.send(:extract_frames, backtrace)

      expect(frames).to include("user.rb:save")
      expect(frames).to include("users_controller.rb:create")
    end

    it "ignores line numbers" do
      backtrace1 = "app/models/user.rb:10:in `save'"
      backtrace2 = "app/models/user.rb:50:in `save'"

      error1 = create(:error_log, backtrace: backtrace1)
      error2 = create(:error_log, backtrace: backtrace2)

      calculator = described_class.new(error1, error2)
      frames1 = calculator.send(:extract_frames, backtrace1)
      frames2 = calculator.send(:extract_frames, backtrace2)

      expect(frames1).to eq(frames2)
    end

    it "limits to first 20 frames" do
      backtrace = (1..50).map { |i| "app/models/user.rb:#{i}:in `method_#{i}'" }.join("\n")
      error = create(:error_log, backtrace: backtrace)

      calculator = described_class.new(error, error)
      frames = calculator.send(:extract_frames, backtrace)

      expect(frames.size).to be <= 20
    end

    it "returns empty array for nil backtrace" do
      error = create(:error_log, backtrace: nil)
      calculator = described_class.new(error, error)

      frames = calculator.send(:extract_frames, nil)
      expect(frames).to eq([])
    end
  end

  describe "#normalize_message" do
    let(:error) { create(:error_log) }
    let(:calculator) { described_class.new(error, error) }

    it "replaces numbers with N" do
      normalized = calculator.send(:normalize_message, "User ID 123 not found")
      expect(normalized).to include("user id n not found")
    end

    it "replaces quoted strings with empty quotes" do
      normalized = calculator.send(:normalize_message, "undefined method \"save\" for User")
      expect(normalized).to include('undefined method "" for user')
    end

    it "replaces hex addresses with 0xHEX" do
      normalized = calculator.send(:normalize_message, "Object ID 0x12abc4de")
      expect(normalized).to include("object id 0xhex")
    end

    it "replaces object inspections with #<OBJ>" do
      normalized = calculator.send(:normalize_message, "Received #<User:0x12abc> instead")
      expect(normalized).to include("received #<obj> instead")
    end

    it "converts to lowercase" do
      normalized = calculator.send(:normalize_message, "ERROR: User Not Found")
      expect(normalized).to eq("error: user not found")
    end

    it "strips whitespace" do
      normalized = calculator.send(:normalize_message, "  error message  ")
      expect(normalized).to eq("error message")
    end

    it "returns empty string for nil" do
      normalized = calculator.send(:normalize_message, nil)
      expect(normalized).to eq("")
    end
  end

  describe "#levenshtein_distance" do
    let(:error) { create(:error_log) }
    let(:calculator) { described_class.new(error, error) }

    it "returns 0 for identical strings" do
      distance = calculator.send(:levenshtein_distance, "hello", "hello")
      expect(distance).to eq(0)
    end

    it "calculates correct distance for different strings" do
      distance = calculator.send(:levenshtein_distance, "kitten", "sitting")
      expect(distance).to eq(3) # k→s, e→i, insert g
    end

    it "returns string length for empty string comparison" do
      distance = calculator.send(:levenshtein_distance, "", "hello")
      expect(distance).to eq(5)

      distance = calculator.send(:levenshtein_distance, "hello", "")
      expect(distance).to eq(5)
    end
  end

  # audit-fixes-0-16-0/REQ-7: Ruby 3.4 writes in 'User#save' where 3.3 wrote
  # in `save'. The frame regex only knew the backtick, so 3.4 frames lost their
  # method and similar-error matching compared bare file names.
  describe "frames from either Ruby's backtrace format" do
    ruby33 = "app/models/user.rb:10:in `save'\napp/models/user.rb:20:in `block in save'"
    ruby34 = "app/models/user.rb:10:in 'User#save'\napp/models/user.rb:20:in 'block in User#save'"

    it "gives a Ruby 3.3 and a Ruby 3.4 line the same frames" do
      calculator = described_class.new(build(:error_log), build(:error_log))

      expect(calculator.send(:extract_frames, ruby34)).to eq(calculator.send(:extract_frames, ruby33))
      expect(calculator.send(:extract_frames, ruby33)).to eq([ "user.rb:save", "user.rb:block in save" ])
    end

    it "gives ErrorLog#backtrace_frames the same frames for both" do
      expect(build(:error_log, backtrace: ruby34).backtrace_frames)
        .to eq(build(:error_log, backtrace: ruby33).backtrace_frames)
    end
  end
end
