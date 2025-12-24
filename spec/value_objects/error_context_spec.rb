# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::ValueObjects::ErrorContext do
  describe '#initialize' do
    context 'with HTTP request context' do
      let(:user) { double('User', id: 123) }
      let(:request) do
        double('Request',
          fullpath: '/users/123',
          params: ActionController::Parameters.new(id: 123, controller: 'users', action: 'show'),
          user_agent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)',
          remote_ip: '192.168.1.1'
        )
      end
      let(:context) { { current_user: user, request: request } }

      subject { described_class.new(context) }

      it 'extracts user_id' do
        expect(subject.user_id).to eq(123)
      end

      it 'builds request_url' do
        expect(subject.request_url).to eq('/users/123')
      end

      it 'extracts user_agent' do
        expect(subject.user_agent).to eq('Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)')
      end

      it 'extracts ip_address' do
        expect(subject.ip_address).to eq('192.168.1.1')
      end

      it 'detects platform' do
        expect(subject.platform).to eq('iOS')
      end

      it 'extracts request params' do
        expect(subject.request_params).to be_a(String)
        params = JSON.parse(subject.request_params)
        expect(params['id']).to eq(123)
      end
    end

    context 'with background job context' do
      let(:job) do
        double('ActiveJob',
          class: double(name: 'TestJob'),
          job_id: 'abc123',
          queue_name: 'default',
          arguments: [ 1, 2, 3 ],
          executions: 1
        )
      end
      let(:context) { { job: job } }

      subject { described_class.new(context) }

      it 'builds request_url for job' do
        expect(subject.request_url).to include('Background Job')
      end

      it 'extracts job params' do
        expect(subject.request_params).to be_a(String)
        params = JSON.parse(subject.request_params)
        expect(params['job_class']).to eq('TestJob')
        expect(params['queue']).to eq('default')
      end

      it 'sets user_agent as Sidekiq Worker' do
        expect(subject.user_agent).to eq('Sidekiq Worker')
      end

      it 'sets ip_address as background_job' do
        expect(subject.ip_address).to eq('background_job')
      end

      it 'detects platform as API' do
        expect(subject.platform).to eq('API')
      end
    end

    context 'with Sidekiq context' do
      let(:context) do
        {
          job_class: 'MyWorker',
          jid: 'xyz789',
          queue: 'urgent',
          retry_count: 2
        }
      end

      subject { described_class.new(context) }

      it 'builds request_url for Sidekiq' do
        expect(subject.request_url).to eq('Sidekiq: MyWorker')
      end

      it 'sets ip_address as sidekiq_worker' do
        expect(subject.ip_address).to eq('sidekiq_worker')
      end
    end

    context 'with minimal context' do
      let(:context) { {} }

      subject { described_class.new(context) }

      it 'uses defaults' do
        expect(subject.user_id).to be_nil
        expect(subject.request_url).to eq('Rails Application')
        expect(subject.user_agent).to eq('Rails Application')
        expect(subject.ip_address).to eq('application_layer')
        expect(subject.platform).to eq('API')
      end
    end

    context 'with custom source' do
      let(:context) { {} }
      let(:source) { 'Custom Service' }

      subject { described_class.new(context, source) }

      it 'uses source as request_url' do
        expect(subject.request_url).to eq('Custom Service')
      end
    end
  end

  describe '#to_h' do
    let(:context) { { user_id: 456 } }
    subject { described_class.new(context) }

    it 'returns a hash with all attributes' do
      result = subject.to_h
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(:user_id, :request_url, :request_params, :user_agent, :ip_address, :platform, :controller_name, :action_name)
    end
  end
end
