# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Detects the platform (iOS/Android/API) from user agent string
    class PlatformDetector
      def self.detect(user_agent)
        new(user_agent).detect
      end

      def initialize(user_agent)
        @user_agent = user_agent
      end

      def detect
        return 'API' if @user_agent.blank?

        browser = Browser.new(@user_agent)

        if browser.device.iphone? || browser.device.ipad?
          'iOS'
        elsif browser.platform.android?
          'Android'
        elsif @user_agent&.include?('Expo')
          # Expo apps might have specific patterns
          if @user_agent.include?('iOS')
            'iOS'
          elsif @user_agent.include?('Android')
            'Android'
          else
            'Mobile'
          end
        else
          'API'
        end
      end
    end
  end
end
