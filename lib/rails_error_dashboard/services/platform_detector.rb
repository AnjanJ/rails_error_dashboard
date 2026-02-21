# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Detects the platform (iOS/Android/API) from user agent string.
    # Uses the browser gem when available, falls back to regex matching.
    class PlatformDetector
      def self.detect(user_agent)
        new(user_agent).detect
      end

      def initialize(user_agent)
        @user_agent = user_agent
      end

      def detect
        return "API" if @user_agent.blank?

        if defined?(Browser)
          detect_with_browser_gem
        else
          detect_with_regex
        end
      end

      private

      def detect_with_browser_gem
        browser = Browser.new(@user_agent)

        if browser.device.iphone? || browser.device.ipad?
          "iOS"
        elsif browser.platform.android?
          "Android"
        elsif @user_agent&.include?("Expo")
          detect_expo_platform
        else
          "API"
        end
      end

      def detect_with_regex
        case @user_agent
        when /iPhone|iPad|iPod/i
          "iOS"
        when /Android/i
          "Android"
        when /Expo/
          detect_expo_platform
        else
          "API"
        end
      end

      def detect_expo_platform
        if @user_agent.include?("iOS")
          "iOS"
        elsif @user_agent.include?("Android")
          "Android"
        else
          "Mobile"
        end
      end
    end
  end
end
