# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::AiAgentClassifier do
  describe ".kind" do
    # Table-driven: the value of this class is entirely in the mapping, so the
    # mapping is what the spec asserts.
    {
      "ChatGPT-User/1.0; +https://openai.com/bot" => :ai_assistant,
      "Claude-User/1.0" => :ai_assistant,
      "Mozilla/5.0 (compatible; GPTBot/1.2; +https://openai.com/gptbot)" => :ai_crawler,
      "Mozilla/5.0 (compatible; ClaudeBot/1.0; +claudebot@anthropic.com)" => :ai_crawler,
      "PerplexityBot/1.0" => :ai_crawler,
      "OAI-SearchBot/1.0" => :ai_crawler,
      "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" => :crawler,
      "Mozilla/5.0 (compatible; bingbot/2.0)" => :crawler,
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0" => :browser,
      "curl/8.4.0" => :library,
      "python-requests/2.31.0" => :library,
      "SomeUnknownThing/9" => :other,
      "" => :other,
      nil => :other
    }.each do |ua, expected|
      it "classifies #{ua.inspect[0, 45]} as #{expected}" do
        expect(described_class.kind(ua)).to eq(expected)
      end
    end

    # The trap this guards: most bots embed a full browser UA string, so a
    # browser-first check would misfile nearly every crawler as :browser.
    it "prefers the bot signature over an embedded browser string" do
      ua = "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.2)"
      expect(described_class.kind(ua)).to eq(:ai_crawler)
    end
  end

  describe ".name" do
    it "returns the canonical agent name" do
      expect(described_class.name("Mozilla/5.0 (compatible; ClaudeBot/1.0)")).to eq("ClaudeBot")
    end

    it "returns nil for an unrecognised agent rather than guessing" do
      expect(described_class.name("TotallyNovelAgent/1.0")).to be_nil
    end

    it "returns nil for a plain browser" do
      expect(described_class.name("Mozilla/5.0 (Windows NT 10.0) Chrome/120.0")).to be_nil
    end

    it "returns nil for blank input" do
      expect(described_class.name(nil)).to be_nil
      expect(described_class.name("")).to be_nil
    end
  end

  describe ".ai?" do
    it "is true for assistants and crawlers alike" do
      expect(described_class.ai?("ChatGPT-User/1.0")).to be true
      expect(described_class.ai?("GPTBot/1.2")).to be true
    end

    it "is false for search crawlers, browsers and libraries" do
      expect(described_class.ai?("Googlebot/2.1")).to be false
      expect(described_class.ai?("Mozilla/5.0 Chrome/120.0")).to be false
      expect(described_class.ai?("curl/8.4.0")).to be false
    end
  end

  describe ".classify" do
    it "returns kind, name and ai in one pass" do
      expect(described_class.classify("PerplexityBot/1.0")).to eq(
        kind: :ai_crawler, name: "PerplexityBot", ai: true
      )
    end
  end

  describe "safety" do
    it "never raises on a non-string input" do
      expect { described_class.kind(Object.new) }.not_to raise_error
      expect(described_class.kind(Object.new)).to eq(:other)
    end
  end
end
