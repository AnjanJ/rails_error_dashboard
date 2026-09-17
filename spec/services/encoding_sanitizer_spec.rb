# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::EncodingSanitizer do
  describe ".scrub" do
    it "returns the same object for a valid UTF-8 string (fast path)" do
      str = +"ok"
      expect(described_class.scrub(str)).to equal(str)
    end

    it "returns the same object for a valid frozen string" do
      str = "ok"
      expect(described_class.scrub(str)).to equal(str)
    end

    it "replaces invalid bytes in a binary string with ?" do
      result = described_class.scrub("caf\xC3 \xFF".b)

      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result).to be_valid_encoding
      expect(result).to include("?")
      expect(result).to start_with("caf")
    end

    it "replaces invalid bytes in a string tagged UTF-8" do
      result = described_class.scrub((+"bad \xFF\xFE bytes").force_encoding(Encoding::UTF_8))

      expect(result).to be_valid_encoding
      expect(result).to eq("bad ?? bytes")
    end

    it "strips NUL bytes" do
      result = described_class.scrub("a\0b")

      expect(result).to eq("ab")
    end

    it "re-tags ASCII-8BIT input as UTF-8 without transcoding" do
      binary = "h\xC3\xA9llo".b
      result = described_class.scrub(binary)

      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result).to eq("héllo")
      expect(binary.encoding).to eq(Encoding::ASCII_8BIT) # caller's string untouched
    end

    it "re-tags other encodings and scrubs rather than raising" do
      latin = "caf\xE9".dup.force_encoding(Encoding::ISO_8859_1)
      result = described_class.scrub(latin)

      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result).to be_valid_encoding
    end

    it "does not raise on frozen invalid input" do
      frozen = "x\xFF".b.freeze

      expect { described_class.scrub(frozen) }.not_to raise_error
      expect(described_class.scrub(frozen)).to eq("x?")
    end

    it "returns non-strings untouched" do
      obj = Object.new
      expect(described_class.scrub(nil)).to be_nil
      expect(described_class.scrub(42)).to eq(42)
      expect(described_class.scrub(:sym)).to eq(:sym)
      expect(described_class.scrub(obj)).to equal(obj)
    end

    it "falls back to a placeholder when scrubbing itself raises" do
      str = +"x\xFF"
      allow(str).to receive(:valid_encoding?).and_raise(RuntimeError, "boom")

      expect(described_class.scrub(str)).to eq("[unreadable]")
    end
  end

  describe ".scrub_deep" do
    it "walks hash keys and values and arrays" do
      input = { "k\xFF".b => [ "v\xFE".b, { nested: "n\0n" } ], ok: "fine" }
      result = described_class.scrub_deep(input)

      expect(result.keys).to eq([ "k?", :ok ])
      expect(result["k?"]).to eq([ "v?", { nested: "nn" } ])
      expect(result[:ok]).to eq("fine")
    end

    it "leaves Integer, nil, Symbol, true and Float alone" do
      input = { a: 1, b: nil, c: :sym, d: true, e: 1.5 }
      expect(described_class.scrub_deep(input)).to eq(input)
    end

    it "preserves ActiveSupport::HashWithIndifferentAccess" do
      input = ActiveSupport::HashWithIndifferentAccess.new("a" => "x\xFF".b)
      result = described_class.scrub_deep(input)

      expect(result).to be_a(ActiveSupport::HashWithIndifferentAccess)
      expect(result[:a]).to eq("x?")
    end

    it "handles a 5-level nest" do
      input = { a: { b: { c: { d: { e: "deep\xFF".b } } } } }
      expect(described_class.scrub_deep(input).dig(:a, :b, :c, :d, :e)).to eq("deep?")
    end

    it "stops at depth 10, replacing the deeper subtree rather than passing it through unscrubbed" do
      deep = "leaf\xFF".b
      15.times { deep = [ deep ] }

      result = described_class.scrub_deep(deep)

      expect(result.flatten).to eq([ described_class::TOO_DEEP ])
    end

    it "does not loop forever on a self-referencing structure" do
      loopy = []
      loopy << loopy

      expect { described_class.scrub_deep(loopy) }.not_to raise_error
    end

    it "returns unknown objects untouched" do
      obj = Object.new
      expect(described_class.scrub_deep(obj)).to equal(obj)
      expect(described_class.scrub_deep([ obj ]).first).to equal(obj)
    end

    it "does not mutate its input" do
      inner = "v\xFF".b
      input = { a: [ inner ] }
      described_class.scrub_deep(input)

      expect(input[:a].first).to equal(inner)
      expect(inner.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it "never raises, whatever it is given" do
      [ Object.new, nil, 1, :a, "\xC3".b, [ [ [ "\xFF".b ] ] ], { 1 => { 2 => "\0" } }, Class, BasicObject ].each do |value|
        expect { described_class.scrub_deep(value) }.not_to raise_error
      end
    end
  end
end
