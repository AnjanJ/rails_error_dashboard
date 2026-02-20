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
          remote_ip: '192.168.1.1',
          request_id: 'req-abc-123',
          session: double('Session', id: 'sess-xyz-456'),
          method: 'POST',
          host: 'example.com',
          content_type: 'application/json',
          env: { "rails_error_dashboard.request_start" => Time.now.to_f - 0.150 }
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

      it 'extracts http_method' do
        expect(subject.http_method).to eq('POST')
      end

      it 'extracts hostname' do
        expect(subject.hostname).to eq('example.com')
      end

      it 'extracts content_type' do
        expect(subject.content_type).to eq('application/json')
      end

      it 'calculates request_duration_ms' do
        expect(subject.request_duration_ms).to be_a(Integer)
        expect(subject.request_duration_ms).to be_between(100, 300)
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
        expect(subject.http_method).to be_nil
        expect(subject.hostname).to be_nil
        expect(subject.content_type).to be_nil
        expect(subject.request_duration_ms).to be_nil
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

    context 'with explicit enriched context (no request object)' do
      let(:context) do
        {
          http_method: 'DELETE',
          hostname: 'api.example.com',
          content_type: 'text/html',
          request_duration_ms: 250
        }
      end

      subject { described_class.new(context) }

      it 'extracts http_method from explicit context' do
        expect(subject.http_method).to eq('DELETE')
      end

      it 'extracts hostname from explicit context' do
        expect(subject.hostname).to eq('api.example.com')
      end

      it 'extracts content_type from explicit context' do
        expect(subject.content_type).to eq('text/html')
      end

      it 'extracts request_duration_ms from explicit context' do
        expect(subject.request_duration_ms).to eq(250)
      end
    end
  end

    context 'with CurrentAttributes auto-detection' do
      let(:context) { {} }
      subject { described_class.new(context) }

      context 'when Current.user is defined' do
        let(:current_user) { double('User', id: 789) }

        before do
          current_class = Class.new do
            def self.user; end
            def self.request_id; end
          end
          stub_const('Current', current_class)
          allow(Current).to receive(:user).and_return(current_user)
          allow(Current).to receive(:request_id).and_return('req-from-current')
        end

        it 'extracts user_id from CurrentAttributes' do
          expect(subject.user_id).to eq(789)
        end

        it 'extracts request_id from CurrentAttributes' do
          expect(subject.request_id).to eq('req-from-current')
        end
      end

      context 'when explicit context takes priority over CurrentAttributes' do
        let(:explicit_user) { double('User', id: 111) }
        let(:current_user) { double('User', id: 999) }
        let(:context) { { current_user: explicit_user } }

        before do
          current_class = Class.new do
            def self.user; end
          end
          stub_const('Current', current_class)
          allow(Current).to receive(:user).and_return(current_user)
        end

        it 'uses explicit user_id over CurrentAttributes' do
          expect(subject.user_id).to eq(111)
        end
      end

      context 'when Current.user is nil' do
        before do
          current_class = Class.new do
            def self.user; end
          end
          stub_const('Current', current_class)
          allow(Current).to receive(:user).and_return(nil)
        end

        it 'returns nil for user_id' do
          expect(subject.user_id).to be_nil
        end
      end

      context 'when Current does not define user' do
        before do
          stub_const('Current', Class.new)
        end

        it 'returns nil for user_id' do
          expect(subject.user_id).to be_nil
        end
      end

      context 'when Current is not defined' do
        it 'returns nil for user_id' do
          expect(subject.user_id).to be_nil
        end

        it 'returns nil for request_id' do
          expect(subject.request_id).to be_nil
        end
      end

      context 'when CurrentAttributes raises an error' do
        before do
          current_class = Class.new do
            def self.user
              raise "database connection lost"
            end
          end
          stub_const('Current', current_class)
        end

        it 'returns nil gracefully' do
          expect(subject.user_id).to be_nil
        end
      end
    end

  describe '#to_h' do
    let(:context) { { user_id: 456 } }
    subject { described_class.new(context) }

    it 'returns a hash with all attributes' do
      result = subject.to_h
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(
        :user_id, :request_url, :request_params, :user_agent, :ip_address, :platform,
        :controller_name, :action_name, :http_method, :hostname, :content_type, :request_duration_ms
      )
    end
  end
end
