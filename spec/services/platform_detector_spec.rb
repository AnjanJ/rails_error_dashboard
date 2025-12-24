# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/rails_error_dashboard/services/platform_detector'

RSpec.describe RailsErrorDashboard::Services::PlatformDetector do
  describe '.detect' do
    context 'with iOS user agent' do
      it 'detects iPhone' do
        user_agent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15'
        expect(described_class.detect(user_agent)).to eq('iOS')
      end

      it 'detects iPad' do
        user_agent = 'Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15'
        expect(described_class.detect(user_agent)).to eq('iOS')
      end

      it 'detects Expo iOS' do
        user_agent = 'Expo/1.0.0 iOS/16.0'
        expect(described_class.detect(user_agent)).to eq('iOS')
      end
    end

    context 'with Android user agent' do
      it 'detects Android device' do
        user_agent = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36'
        expect(described_class.detect(user_agent)).to eq('Android')
      end

      it 'detects Expo Android' do
        user_agent = 'Expo/1.0.0 Android/13'
        expect(described_class.detect(user_agent)).to eq('Android')
      end
    end

    context 'with API/backend user agents' do
      it 'detects Rails Application' do
        user_agent = 'Rails Application'
        expect(described_class.detect(user_agent)).to eq('API')
      end

      it 'detects Sidekiq Worker' do
        user_agent = 'Sidekiq Worker'
        expect(described_class.detect(user_agent)).to eq('API')
      end

      it 'detects Ruby HTTP client' do
        user_agent = 'Ruby/3.2.0'
        expect(described_class.detect(user_agent)).to eq('API')
      end
    end

    context 'with blank user agent' do
      it 'returns API' do
        expect(described_class.detect(nil)).to eq('API')
        expect(described_class.detect('')).to eq('API')
      end
    end

    context 'with Expo user agent without specific platform' do
      it 'returns Mobile' do
        user_agent = 'Expo/1.0.0'
        expect(described_class.detect(user_agent)).to eq('Mobile')
      end
    end

    context 'with web browser user agents' do
      it 'returns API for desktop browsers' do
        user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0.0.0'
        expect(described_class.detect(user_agent)).to eq('API')
      end
    end
  end
end
