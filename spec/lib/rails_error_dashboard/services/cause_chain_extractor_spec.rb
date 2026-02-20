# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::CauseChainExtractor do
  describe ".call" do
    context "when exception has no cause" do
      it "returns nil" do
        error = StandardError.new("no cause")
        expect(described_class.call(error)).to be_nil
      end
    end

    context "when exception has a single cause" do
      it "returns JSON with one cause entry" do
        error = build_chained_exception(
          StandardError.new("outer"),
          ArgumentError.new("inner")
        )

        result = described_class.call(error)
        parsed = JSON.parse(result)

        expect(parsed).to be_an(Array)
        expect(parsed.length).to eq(1)
        expect(parsed[0]["class_name"]).to eq("ArgumentError")
        expect(parsed[0]["message"]).to eq("inner")
      end
    end

    context "when exception has a multi-level cause chain" do
      it "captures all causes in order (outermost cause first)" do
        # Build chain: error -> cause1 -> cause2
        error = build_three_level_chain(
          StandardError.new("outer error"),
          IOError.new("middle error"),
          RuntimeError.new("root cause")
        )

        result = described_class.call(error)
        parsed = JSON.parse(result)

        expect(parsed.length).to eq(2)
        expect(parsed[0]["class_name"]).to eq("IOError")
        expect(parsed[0]["message"]).to eq("middle error")
        expect(parsed[1]["class_name"]).to eq("RuntimeError")
        expect(parsed[1]["message"]).to eq("root cause")
      end
    end

    context "when exception cause has a backtrace" do
      it "includes truncated backtrace in the output" do
        inner = ArgumentError.new("inner")
        inner.set_backtrace([ "app/models/user.rb:10:in `validate'", "app/controllers/users_controller.rb:5:in `create'" ])

        error = build_chained_exception(StandardError.new("outer"), inner)

        result = described_class.call(error)
        parsed = JSON.parse(result)

        expect(parsed[0]["backtrace"]).to be_an(Array)
        expect(parsed[0]["backtrace"].length).to eq(2)
        expect(parsed[0]["backtrace"][0]).to include("user.rb")
      end
    end

    context "when backtrace exceeds MAX_BACKTRACE_LINES" do
      it "truncates backtrace to 20 lines" do
        inner = ArgumentError.new("inner")
        inner.set_backtrace(30.times.map { |i| "app/file#{i}.rb:#{i}:in `method#{i}'" })

        error = build_chained_exception(StandardError.new("outer"), inner)

        result = described_class.call(error)
        parsed = JSON.parse(result)

        expect(parsed[0]["backtrace"].length).to eq(20)
      end
    end

    context "when message exceeds MAX_MESSAGE_LENGTH" do
      it "truncates message to 1000 characters" do
        long_message = "x" * 2000
        inner = ArgumentError.new(long_message)

        error = build_chained_exception(StandardError.new("outer"), inner)

        result = described_class.call(error)
        parsed = JSON.parse(result)

        expect(parsed[0]["message"].length).to eq(1000)
      end
    end

    context "depth limit safety" do
      it "stops at MAX_DEPTH (5) levels" do
        # Build a chain 7 levels deep using nested rescue/raise
        error = build_deep_chain(7)

        result = described_class.call(error)
        parsed = JSON.parse(result)

        # Should have at most 5 causes (depth limit)
        expect(parsed.length).to be <= 5
      end
    end

    context "when cause has backtrace from raise" do
      it "captures the backtrace set by Ruby" do
        # When you raise inside rescue, Ruby sets backtrace automatically
        error = build_chained_exception(
          StandardError.new("outer"),
          ArgumentError.new("inner with backtrace")
        )

        result = described_class.call(error)
        parsed = JSON.parse(result)

        # Ruby sets backtrace when exceptions are raised
        expect(parsed[0]["backtrace"]).to be_an(Array)
        expect(parsed[0]["backtrace"]).not_to be_empty
      end
    end

    context "error safety" do
      it "returns nil if extraction fails" do
        error = StandardError.new("test")
        # Simulate a problematic cause that raises on access
        allow(error).to receive(:cause).and_raise(RuntimeError.new("cause access failed"))

        expect(described_class.call(error)).to be_nil
      end
    end
  end

  private

  # Build a two-level exception chain using Ruby's built-in cause mechanism
  def build_chained_exception(outer, inner)
    begin
      begin
        raise inner
      rescue
        raise outer
      end
    rescue => e
      e
    end
  end

  # Build a three-level chain: outer -> middle -> root
  def build_three_level_chain(outer, middle, root)
    begin
      begin
        begin
          raise root
        rescue
          raise middle
        end
      rescue
        raise outer
      end
    rescue => e
      e
    end
  end

  # Build a deep chain of N levels for depth limit testing
  def build_deep_chain(depth)
    exceptions = depth.times.map { |i| StandardError.new("level #{i}") }

    # Build from innermost to outermost using recursive rescue/raise
    result = nil
    begin
      raise exceptions.last
    rescue => innermost
      result = innermost
    end

    exceptions[0...-1].reverse_each do |exc|
      begin
        begin
          raise result
        rescue
          raise exc
        end
      rescue => e
        result = e
      end
    end

    result
  end
end
