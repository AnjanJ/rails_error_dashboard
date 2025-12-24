# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::LogError do
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
      let(:request) { double('Request', fullpath: '/users/1', params: { id: 1 }, user_agent: 'Chrome', remote_ip: '127.0.0.1') }
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
  end
end
