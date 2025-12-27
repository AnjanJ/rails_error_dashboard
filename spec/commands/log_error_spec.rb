# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::LogError do
  before do
    # Ensure async_logging is disabled for synchronous test expectations
    RailsErrorDashboard.configure do |config|
      config.async_logging = false
    end
  end

  after do
    RailsErrorDashboard.reset_configuration!
  end

  describe '.call' do
    let(:exception) do
      begin
        raise StandardError, 'Test error'
      rescue => e
        e
      end
    end
    let(:context) { {} }

    it 'creates an error log' do
      expect {
        described_class.call(exception, context)
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
    end

    it 'stores the error type' do
      described_class.call(exception, context)
      error_log = RailsErrorDashboard::ErrorLog.last
      expect(error_log.error_type).to eq('StandardError')
    end

    it 'stores the error message' do
      described_class.call(exception, context)
      error_log = RailsErrorDashboard::ErrorLog.last
      expect(error_log.message).to eq('Test error')
    end

    it 'stores the backtrace' do
      described_class.call(exception, context)
      error_log = RailsErrorDashboard::ErrorLog.last
      expect(error_log.backtrace).to be_present
    end

    it 'sets occurred_at to current time' do
      freeze_time do
        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.occurred_at).to be_within(1.second).of(Time.current)
      end
    end

    context 'with user context' do
      let(:user) { double('User', id: 123) }
      let(:context) { { current_user: user } }

      it 'stores the user_id' do
        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.user_id).to eq(123)
      end
    end

    context 'with request context' do
      let(:request) do
        double('Request',
          fullpath: '/users/1',
          params: { id: 1 },
          user_agent: 'Chrome',
          remote_ip: '127.0.0.1',
          request_id: 'req-test-123',
          session: double('Session', id: 'sess-test-456')
        )
      end
      let(:context) { { request: request } }

      before do
        allow(request).to receive(:params).and_return(ActionController::Parameters.new(id: 1, controller: 'users', action: 'show'))
      end

      it 'stores request URL' do
        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.request_url).to eq('/users/1')
      end

      it 'stores request params' do
        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.request_params).to be_present
      end

      it 'stores user agent' do
        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.user_agent).to eq('Chrome')
      end

      it 'stores IP address' do
        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.ip_address).to eq('127.0.0.1')
      end
    end

    context 'with mobile app context' do
      let(:context) do
        {
          source: :mobile_app,
          additional_context: {
            component: 'RecordingScreen',
            device_info: { platform: 'iOS', version: '16.0' }
          }
        }
      end

      it 'creates error log successfully' do
        result = described_class.call(exception, context)
        expect(result).not_to be_nil
        expect(result).to be_a(RailsErrorDashboard::ErrorLog)
        expect(result).to be_persisted
      end
    end

    context 'with notifications enabled', :vcr do
      before do
        allow(RailsErrorDashboard.configuration).to receive(:enable_slack_notifications).and_return(true)
        allow(RailsErrorDashboard.configuration).to receive(:slack_webhook_url).and_return('https://hooks.slack.com/test')
      end

      it 'enqueues Slack notification job' do
        expect {
          described_class.call(exception, context)
        }.to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
      end
    end

    context 'with email notifications enabled' do
      before do
        allow(RailsErrorDashboard.configuration).to receive(:enable_email_notifications).and_return(true)
        allow(RailsErrorDashboard.configuration).to receive(:notification_email_recipients).and_return([ 'dev@example.com' ])
      end

      it 'enqueues email notification job' do
        expect {
          described_class.call(exception, context)
        }.to have_enqueued_job(RailsErrorDashboard::EmailErrorNotificationJob)
      end
    end

    context 'error deduplication' do
      let(:exception) do
        begin
          raise NoMethodError, "undefined method `name' for nil:NilClass"
        rescue => e
          e
        end
      end

      it 'generates error hash for new errors' do
        error_log = described_class.call(exception, context)
        expect(error_log.error_hash).to be_present
        expect(error_log.error_hash.length).to eq(16)
      end

      it 'sets occurrence_count to 1 for new errors' do
        error_log = described_class.call(exception, context)
        expect(error_log.occurrence_count).to eq(1)
      end

      it 'sets first_seen_at and last_seen_at for new errors' do
        freeze_time do
          error_log = described_class.call(exception, context)
          expect(error_log.first_seen_at).to be_within(1.second).of(Time.current)
          expect(error_log.last_seen_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'increments occurrence_count when same error occurs again' do
        # First occurrence
        error1 = described_class.call(exception, context)
        expect(error1.occurrence_count).to eq(1)

        # Second occurrence (same exception)
        error2 = described_class.call(exception, context)
        expect(error2.id).to eq(error1.id)
        expect(error2.occurrence_count).to eq(2)
      end

      it 'preserves first_seen_at but updates last_seen_at on recurrence' do
        # First occurrence
        first_time = 2.hours.ago
        travel_to(first_time) do
          @error1 = described_class.call(exception, context)
        end

        # Second occurrence
        second_time = 1.hour.ago
        travel_to(second_time) do
          @error2 = described_class.call(exception, context)
        end

        expect(@error2.id).to eq(@error1.id)
        expect(@error2.first_seen_at).to be_within(1.second).of(first_time)
        expect(@error2.last_seen_at).to be_within(1.second).of(second_time)
      end

      it 'sends notification only on first occurrence' do
        allow(RailsErrorDashboard.configuration).to receive(:enable_slack_notifications).and_return(true)
        allow(RailsErrorDashboard.configuration).to receive(:slack_webhook_url).and_return('https://hooks.slack.com/test')

        # First occurrence - should send notification
        expect {
          described_class.call(exception, context)
        }.to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob).once

        # Second occurrence - should NOT send notification
        expect {
          described_class.call(exception, context)
        }.not_to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
      end

      it 'creates new error when resolved error recurs' do
        # First occurrence
        error1 = described_class.call(exception, context)
        error1.update!(resolved: true, resolved_at: Time.current)

        # Second occurrence (regression)
        error2 = described_class.call(exception, context)
        expect(error2.id).not_to eq(error1.id)
        expect(error2.occurrence_count).to eq(1)
        expect(error2.resolved).to be false
      end

      it 'creates new error when old error (>24h) recurs' do
        # Error from 2 days ago
        old_error = nil
        travel_to(2.days.ago) do
          old_error = described_class.call(exception, context)
        end

        # Same error today
        new_error = described_class.call(exception, context)
        expect(new_error.id).not_to eq(old_error.id)
        expect(new_error.occurrence_count).to eq(1)
      end

      it 'normalizes dynamic values in error messages' do
        # Different user IDs should generate same hash
        exception1 = begin
          raise ArgumentError, "Invalid user ID: 123"
        rescue => e
          e
        end

        exception2 = begin
          raise ArgumentError, "Invalid user ID: 456"
        rescue => e
          e
        end

        error1 = described_class.call(exception1, context)
        error2 = described_class.call(exception2, context)

        expect(error1.error_hash).to eq(error2.error_hash)
        expect(error2.id).to eq(error1.id)
        expect(error2.occurrence_count).to eq(2)
      end

      it 'creates separate errors for different error types' do
        exception1 = begin
          raise NoMethodError, "undefined method `name'"
        rescue => e
          e
        end

        exception2 = begin
          raise ArgumentError, "undefined method `name'"
        rescue => e
          e
        end

        error1 = described_class.call(exception1, context)
        error2 = described_class.call(exception2, context)

        expect(error1.error_hash).not_to eq(error2.error_hash)
        expect(error2.id).not_to eq(error1.id)
      end

      it 'updates context with latest occurrence data' do
        user1 = double('User', id: 123)
        user2 = double('User', id: 456)

        # First occurrence with user 123
        error1 = described_class.call(exception, { current_user: user1 })
        expect(error1.user_id).to eq(123)

        # Second occurrence with user 456
        error2 = described_class.call(exception, { current_user: user2 })
        expect(error2.id).to eq(error1.id)
        expect(error2.user_id).to eq(456)
      end
    end
  end
end
