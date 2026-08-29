# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::AiAgentClassifier do
  describe ".kind" do
    # Table-driven: the value of this class is entirely in the mapping, so the
    # mapping is what the spec asserts.
    {
      "ChatGPT-User/1.0; +https://openai.com/bot" => :ai_assistant,
      "Claude-User/1.0" => :ai_assistant,
      "GitHubCopilotRuntime-WebFetch" => :ai_assistant,
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

  # Reported from production traffic on issue #170: 7 requests from 5 IPs.
  # Absent from GitHub's docs, ai-robots-txt/ai.robots.txt and Dark Visitors as
  # of 2026-08-29, so the pattern matches observed reality rather than a guess.
  describe "GitHub Copilot" do
    it "names the observed runtime agent and counts it as AI" do
      ua = "GitHubCopilotRuntime-WebFetch"

      expect(described_class.name(ua)).to eq("GitHub Copilot")
      expect(described_class.kind(ua)).to eq(:ai_assistant)
      expect(described_class.ai?(ua)).to be true
    end

    it "matches other GitHubCopilotRuntime suffixes" do
      expect(described_class.name("GitHubCopilotRuntime/1.0")).to eq("GitHub Copilot")
    end

    # A bare /Copilot/i would swallow ordinary browser traffic: Microsoft applies
    # the Copilot brand broadly, and its agentic features are documented as
    # sending plain Edge/Chromium user agents with no bot signal. Mislabelling a
    # human's browser as an AI agent is exactly the wrong-attribution failure the
    # classifier exists to avoid.
    it "does not claim unrelated Copilot-branded browser traffic" do
      edge = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Edg/120.0"

      expect(described_class.ai?(edge)).to be false
      expect(described_class.kind(edge)).to eq(:browser)
      expect(described_class.ai?("Mozilla/5.0 Copilot")).to be false
    end
  end
end
