# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Classifies a User-Agent string into a coarse traffic kind, and names the
    # agent when it is a recognised one.
    #
    # WHY THIS EXISTS (issue #170): tracking which AI agents read an app is the
    # reason people reach for Rack::Attack's `track` rules now. Counting IPs
    # cannot answer it — one agent is a rotating fleet of hundreds of addresses,
    # so unique-IP totals overstate the population badly. The user agent is the
    # signal that actually identifies the reader.
    #
    # Deliberately plain string matching, NOT the `browser` gem: `browser` is an
    # optional dependency that degrades gracefully everywhere else in this gem,
    # and it does not know these agents anyway. This runs on the flush path, not
    # the request path, but it stays allocation-cheap regardless.
    #
    # The bot lists are necessarily a snapshot. An unrecognised agent falls back
    # to :other rather than being guessed at — a wrong attribution is worse than
    # an honest "unknown" when the whole point is measurement.
    class AiAgentClassifier
      # Order matters: the first match wins, so more specific patterns lead.
      #
      # AI agents split into two behaviours worth telling apart, because they
      # answer different questions:
      # - :ai_assistant — fetches on demand, because a human asked something now
      # - :ai_crawler   — bulk-fetches to build a training corpus or index
      AI_ASSISTANTS = {
        "ChatGPT-User" => /ChatGPT-User/i,
        "Claude-User" => /Claude-User/i,
        "Claude Code" => /Claude-?Code/i,
        "Perplexity-User" => /Perplexity-User/i,
        "Gemini-User" => /Gemini-User/i
      }.freeze

      AI_CRAWLERS = {
        "GPTBot" => /GPTBot/i,
        "OAI-SearchBot" => /OAI-SearchBot/i,
        "ClaudeBot" => /ClaudeBot/i,
        "anthropic-ai" => /anthropic-ai/i,
        "PerplexityBot" => /PerplexityBot/i,
        "Google-Extended" => /Google-Extended/i,
        "Applebot-Extended" => /Applebot-Extended/i,
        "Bytespider" => /Bytespider/i,
        "CCBot" => /CCBot/i,
        "Meta-ExternalAgent" => /Meta-ExternalAgent/i,
        "Amazonbot" => /Amazonbot/i,
        "cohere-ai" => /cohere-ai/i,
        "DuckAssistBot" => /DuckAssistBot/i,
        "YouBot" => /YouBot/i,
        "Diffbot" => /Diffbot/i,
        "Timpibot" => /Timpibot/i
      }.freeze

      # Conventional search/SEO crawlers. Not AI traffic, but worth naming so
      # they can be excluded rather than silently inflating an "unknown" bucket.
      CRAWLERS = {
        "Googlebot" => /Googlebot/i,
        "Bingbot" => /bingbot/i,
        "DuckDuckBot" => /DuckDuckBot/i,
        "Baiduspider" => /Baiduspider/i,
        "YandexBot" => /YandexBot/i,
        "AhrefsBot" => /AhrefsBot/i,
        "SemrushBot" => /SemrushBot/i,
        "Applebot" => /Applebot/i,
        "facebookexternalhit" => /facebookexternalhit/i,
        "LLMS-Txt-Scanner" => /LLMS-Txt-Scanner/i
      }.freeze

      # Checked only after every bot pattern has missed, because plenty of bots
      # embed a full browser UA string and would match these first.
      BROWSER_HINTS = /Mozilla|Chrome|Safari|Firefox|Edge|Opera|Gecko|WebKit/i

      # Non-browser HTTP clients — usually scripts, monitors or scrapers.
      LIBRARIES = {
        "curl" => /\bcurl\//i,
        "wget" => /\bWget\//i,
        "python-requests" => /python-requests/i,
        "httpx" => /\bhttpx\//i,
        "Go-http-client" => /Go-http-client/i,
        "Java" => /\bJava\//i,
        "okhttp" => /\bokhttp\//i,
        "axios" => /\baxios\//i,
        "Faraday" => /Faraday/i,
        "RubyGems" => /Ruby\b/i
      }.freeze

      KINDS = %i[ai_assistant ai_crawler crawler browser library other].freeze

      class << self
        # @param user_agent [String, nil]
        # @return [Symbol] one of KINDS
        def kind(user_agent)
          ua = user_agent.to_s
          return :other if ua.strip.empty?

          return :ai_assistant if match_name(AI_ASSISTANTS, ua)
          return :ai_crawler if match_name(AI_CRAWLERS, ua)
          return :crawler if match_name(CRAWLERS, ua)
          return :library if match_name(LIBRARIES, ua)
          return :browser if ua.match?(BROWSER_HINTS)

          :other
        rescue => e
          :other
        end

        # Canonical name for a recognised agent, or nil when unrecognised.
        # Never invents a name — callers show the raw UA in that case.
        #
        # @param user_agent [String, nil]
        # @return [String, nil]
        def name(user_agent)
          ua = user_agent.to_s
          return nil if ua.strip.empty?

          match_name(AI_ASSISTANTS, ua) ||
            match_name(AI_CRAWLERS, ua) ||
            match_name(CRAWLERS, ua) ||
            match_name(LIBRARIES, ua)
        rescue => e
          nil
        end

        # Whether this agent is an LLM reader of either flavour. This is the
        # predicate the dashboard's "AI agents" figure counts.
        #
        # @param user_agent [String, nil]
        # @return [Boolean]
        def ai?(user_agent)
          %i[ai_assistant ai_crawler].include?(kind(user_agent))
        end

        # @return [Hash] { kind:, name:, ai: } — one pass for callers that want all three
        def classify(user_agent)
          k = kind(user_agent)
          {
            kind: k,
            name: name(user_agent),
            ai: %i[ai_assistant ai_crawler].include?(k)
          }
        end

        private

        def match_name(table, ua)
          table.each { |agent_name, pattern| return agent_name if ua.match?(pattern) }
          nil
        end
      end
    end
  end
end
