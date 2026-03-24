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
          session: double('Session', id: 'sess-test-456'),
          method: 'GET',
          host: 'localhost',
          content_type: nil,
          env: {}
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

    context 'with muted error and notifications enabled' do
      before do
        allow(RailsErrorDashboard.configuration).to receive(:enable_slack_notifications).and_return(true)
        allow(RailsErrorDashboard.configuration).to receive(:slack_webhook_url).and_return('https://hooks.slack.com/test')
        allow(RailsErrorDashboard.configuration).to receive(:enable_email_notifications).and_return(true)
        allow(RailsErrorDashboard.configuration).to receive(:notification_email_recipients).and_return([ 'dev@example.com' ])
      end

      it 'does not enqueue notification jobs for muted recurring errors' do
        # First occurrence — creates the error and fires notifications
        error_log = described_class.call(exception, context)
        expect(error_log).to be_persisted

        # Mute the error
        error_log.update!(muted: true, muted_at: Time.current, muted_by: "gandalf")

        # Clear enqueued jobs from first occurrence
        clear_enqueued_jobs

        # Second occurrence — same exception, should NOT fire notifications
        expect {
          described_class.call(exception, context)
        }.not_to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
      end

      it 'does not enqueue email notification jobs for muted recurring errors' do
        error_log = described_class.call(exception, context)
        error_log.update!(muted: true, muted_at: Time.current)
        clear_enqueued_jobs

        expect {
          described_class.call(exception, context)
        }.not_to have_enqueued_job(RailsErrorDashboard::EmailErrorNotificationJob)
      end

      it 'still creates the error occurrence when muted' do
        error_log = described_class.call(exception, context)
        error_log.update!(muted: true, muted_at: Time.current)
        initial_count = error_log.occurrence_count

        described_class.call(exception, context)

        expect(error_log.reload.occurrence_count).to be > initial_count
      end

      it 'resumes notifications after unmuting' do
        error_log = described_class.call(exception, context)
        error_log.update!(muted: true, muted_at: Time.current)
        clear_enqueued_jobs

        # While muted — no notification
        described_class.call(exception, context)
        expect(RailsErrorDashboard::SlackErrorNotificationJob).not_to have_been_enqueued

        # Unmute and resolve so next occurrence triggers reopened notification
        error_log.update!(muted: false, muted_at: nil, resolved: true, resolved_at: Time.current)
        clear_enqueued_jobs

        # Next occurrence reopens — should notify again
        expect {
          described_class.call(exception, context)
        }.to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
      end
    end

    context 'backtrace_locations pass-through' do
      it 'passes backtrace_locations to BacktraceProcessor.calculate_signature' do
        expect(RailsErrorDashboard::Services::BacktraceProcessor).to receive(:calculate_signature)
          .with(anything, locations: exception.backtrace_locations)
          .and_call_original

        described_class.call(exception, context)
      end

      it 'works when exception has nil backtrace_locations' do
        allow(exception).to receive(:backtrace_locations).and_return(nil)

        expect {
          described_class.call(exception, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end
    end

    context 'sensitive data filtering' do
      let(:request) do
        double('Request',
          fullpath: '/login?password=secret123',
          params: ActionController::Parameters.new(
            password: 'secret123', username: 'alice', controller: 'sessions', action: 'create'
          ),
          user_agent: 'Chrome',
          remote_ip: '127.0.0.1',
          request_id: 'req-test',
          session: double('Session', id: 'sess-test'),
          method: 'POST',
          host: 'localhost',
          content_type: nil,
          env: {}
        )
      end
      let(:context) { { request: request } }

      it 'does not filter when filter_sensitive_data is false' do
        RailsErrorDashboard.configuration.filter_sensitive_data = false
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!

        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.request_params).to include('secret123')

        RailsErrorDashboard::Services::SensitiveDataFilter.reset!
      end

      it 'filters sensitive params when filter_sensitive_data is true (default)' do
        allow(Rails.application.config).to receive(:filter_parameters).and_return([])
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!

        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.request_params).to include('[FILTERED]')
        expect(error_log.request_params).not_to include('secret123')
        expect(error_log.request_params).to include('alice')

        RailsErrorDashboard::Services::SensitiveDataFilter.reset!
      end
    end

    context 'environment info capture' do
      it 'stores environment_info as JSON when column exists' do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("environment_info")

        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.environment_info).to be_present
        parsed = JSON.parse(error_log.environment_info)
        expect(parsed["ruby_version"]).to eq(RUBY_VERSION)
        expect(parsed["rails_version"]).to eq(Rails.version)
        expect(parsed["gem_versions"]).to be_a(Hash)
      end

      it 'includes database adapter in environment info' do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("environment_info")

        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        parsed = JSON.parse(error_log.environment_info)
        expect(parsed["database_adapter"]).to be_present
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

      it 'reopens resolved error when same error recurs' do
        # First occurrence
        error1 = described_class.call(exception, context)
        error1.update!(resolved: true, status: "resolved", resolved_at: Time.current)

        # Second occurrence (regression) — should reopen, not create new
        error2 = described_class.call(exception, context)
        expect(error2.id).to eq(error1.id)
        expect(error2.resolved).to be false
        expect(error2.status).to eq("new")
        expect(error2.resolved_at).to be_nil
        expect(error2.occurrence_count).to eq(2)
      end

      it 'sends notifications when a resolved error is reopened' do
        allow(RailsErrorDashboard.configuration).to receive(:enable_slack_notifications).and_return(true)
        allow(RailsErrorDashboard.configuration).to receive(:slack_webhook_url).and_return('https://hooks.slack.com/test')

        # First occurrence
        error1 = described_class.call(exception, context)
        error1.update!(resolved: true, status: "resolved", resolved_at: Time.current)

        # Clear cooldown from first notification so reopened error can notify
        RailsErrorDashboard::Services::NotificationThrottler.clear!

        # Reopened — should send notification
        expect {
          described_class.call(exception, context)
        }.to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
      end

      it 'dispatches on_error_reopened plugin event when reopened' do
        # First occurrence
        error1 = described_class.call(exception, context)
        error1.update!(resolved: true, status: "resolved", resolved_at: Time.current)

        expect(RailsErrorDashboard::PluginRegistry).to receive(:dispatch).with(:on_error_reopened, anything)

        described_class.call(exception, context)
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

    context 'notification throttling' do
      before do
        allow(RailsErrorDashboard.configuration).to receive(:enable_slack_notifications).and_return(true)
        allow(RailsErrorDashboard.configuration).to receive(:slack_webhook_url).and_return('https://hooks.slack.com/test')
        RailsErrorDashboard::Services::NotificationThrottler.clear!
      end

      after do
        RailsErrorDashboard::Services::NotificationThrottler.clear!
      end

      it 'does not notify when severity is below minimum' do
        RailsErrorDashboard.configuration.notification_minimum_severity = :critical

        # StandardError is :high severity, not :critical
        expect {
          described_class.call(exception, context)
        }.not_to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
      end

      it 'does not notify reopened error within cooldown' do
        RailsErrorDashboard.configuration.notification_cooldown_minutes = 60

        # First occurrence
        error1 = described_class.call(exception, context)
        error1.update!(resolved: true, status: "resolved", resolved_at: Time.current)

        # Reopened — should be throttled because first occurrence was just notified
        expect {
          described_class.call(exception, context)
        }.not_to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
      end

      it 'notifies recurring error at threshold milestone' do
        RailsErrorDashboard.configuration.notification_threshold_alerts = [ 3 ]

        # Create error with occurrence_count at 2 (next will be 3 = threshold)
        error1 = described_class.call(exception, context)
        error1.update!(occurrence_count: 2)

        # Third occurrence hits threshold → should notify
        expect {
          described_class.call(exception, context)
        }.to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
      end

      it 'does not notify recurring error that is not at milestone' do
        RailsErrorDashboard.configuration.notification_threshold_alerts = [ 10, 50, 100 ]

        # Create error with occurrence_count at 4 (next will be 5 = no milestone)
        error1 = described_class.call(exception, context)
        error1.update!(occurrence_count: 4)

        # Fifth occurrence — no threshold match → no notification
        expect {
          described_class.call(exception, context)
        }.not_to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
      end
    end

    context "local variable capture" do
      before do
        RailsErrorDashboard.configuration.enable_local_variables = true
        RailsErrorDashboard.configuration.filter_sensitive_data = true
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!
      end

      after do
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!
      end

      it "stores filtered local variables when enabled and column exists" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { user_name: "Gandalf", password: "secret123", count: 42 })

        described_class.call(exc, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.local_variables).to be_present
        parsed = JSON.parse(error_log.local_variables)
        expect(parsed["user_name"]["value"]).to eq("Gandalf")
        expect(parsed["password"]["value"]).to eq("[FILTERED]")
        expect(parsed["password"]["filtered"]).to be true
        expect(parsed["count"]["value"]).to eq(42)
      end

      it "does not store local variables when feature is disabled" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")

        RailsErrorDashboard.configuration.enable_local_variables = false
        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { data: "should not be stored" })

        described_class.call(exc, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.local_variables).to be_nil
      end

      it "handles missing local_variables column gracefully" do
        allow(RailsErrorDashboard::ErrorLog).to receive(:column_names)
          .and_return(RailsErrorDashboard::ErrorLog.column_names - [ "local_variables" ])

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { data: "test" })

        expect {
          described_class.call(exc, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end

      it "handles exception without @_red_locals" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")

        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.local_variables).to be_nil
      end

      it "handles VariableSerializer failure gracefully" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { data: "test" })

        # VariableSerializer.call has internal rescue => {} so it never raises to caller.
        # When it fails internally, it returns {} which gets written as "{}".
        allow(RailsErrorDashboard::Services::VariableSerializer).to receive(:call)
          .and_return({})

        # Error log is still created — serializer failure doesn't block capture
        expect {
          described_class.call(exc, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end

      it "still creates error log when VariableSerializer raises" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { data: "test" })

        allow(RailsErrorDashboard::Services::VariableSerializer).to receive(:call)
          .and_raise(RuntimeError, "serializer boom")

        # Serialization failure is isolated — error log is still created
        expect {
          described_class.call(exc, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.read_attribute(:local_variables)).to be_nil
      end

      it "still creates error log when LocalVariableCapturer.extract raises" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")

        allow(RailsErrorDashboard::Services::LocalVariableCapturer).to receive(:extract)
          .and_raise(RuntimeError, "extractor boom")

        expect {
          described_class.call(exception, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.read_attribute(:local_variables)).to be_nil
      end

      it "uses pre-serialized locals from async context" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")

        pre_serialized = { "name" => { type: "String", value: "Gandalf", truncated: false } }
        ctx = context.merge(_serialized_local_variables: pre_serialized)

        # Exception without @_red_locals (async path — already extracted)
        described_class.call(exception, ctx)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.local_variables).to be_present
        parsed = JSON.parse(error_log.local_variables)
        expect(parsed["name"]["value"]).to eq("Gandalf")
      end
    end

    context "instance variable capture" do
      before do
        RailsErrorDashboard.configuration.enable_instance_variables = true
        RailsErrorDashboard.configuration.filter_sensitive_data = true
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!
      end

      after do
        RailsErrorDashboard.configuration.enable_instance_variables = false
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!
      end

      it "stores filtered instance variables when enabled and column exists" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "UsersController",
          :@current_user => "Gandalf",
          :@password => "secret123",
          :@retry_count => 3
        })

        described_class.call(exc, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.read_attribute(:instance_variables)).to be_present
        parsed = JSON.parse(error_log.read_attribute(:instance_variables))
        expect(parsed["_self_class"]["value"]).to eq("UsersController")
        expect(parsed["@current_user"]["value"]).to eq("Gandalf")
        expect(parsed["@password"]["value"]).to eq("[FILTERED]")
        expect(parsed["@password"]["filtered"]).to be true
        expect(parsed["@retry_count"]["value"]).to eq(3)
      end

      it "does not store instance variables when feature is disabled" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")

        RailsErrorDashboard.configuration.enable_instance_variables = false
        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_instance_vars, { _self_class: "Foo", :@data => "should not be stored" })

        described_class.call(exc, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.read_attribute(:instance_variables)).to be_nil
      end

      it "handles missing instance_variables column gracefully" do
        allow(RailsErrorDashboard::ErrorLog).to receive(:column_names)
          .and_return(RailsErrorDashboard::ErrorLog.column_names - [ "instance_variables" ])

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_instance_vars, { _self_class: "Foo", :@data => "test" })

        expect {
          described_class.call(exc, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end

      it "handles exception without @_red_instance_vars" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")

        described_class.call(exception, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.read_attribute(:instance_variables)).to be_nil
      end

      it "uses pre-serialized instance vars from async context" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")

        pre_serialized = {
          "_self_class" => { type: "Metadata", value: "UsersController", truncated: false },
          "@name" => { type: "String", value: "Gandalf", truncated: false }
        }
        ctx = context.merge(_serialized_instance_variables: pre_serialized)

        # Exception without @_red_instance_vars (async path — already extracted)
        described_class.call(exception, ctx)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.read_attribute(:instance_variables)).to be_present
        parsed = JSON.parse(error_log.read_attribute(:instance_variables))
        expect(parsed["_self_class"]["value"]).to eq("UsersController")
        expect(parsed["@name"]["value"]).to eq("Gandalf")
      end

      it "stores complete serialized structure with type, value, and truncated fields" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "OrdersController",
          :@order_id => 42,
          :@status => "pending"
        })

        described_class.call(exc, context)
        parsed = JSON.parse(RailsErrorDashboard::ErrorLog.last.read_attribute(:instance_variables))

        # Verify each ivar has the full structure
        %w[@order_id @status].each do |key|
          expect(parsed[key]).to have_key("type")
          expect(parsed[key]).to have_key("value")
          expect(parsed[key]).to have_key("truncated")
        end
        expect(parsed["@order_id"]["type"]).to eq("Integer")
        expect(parsed["@order_id"]["value"]).to eq(42)
        expect(parsed["@status"]["type"]).to eq("String")
        expect(parsed["@status"]["value"]).to eq("pending")
      end

      it "applies instance_variable_filter_patterns to serialization" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")

        RailsErrorDashboard.configuration.instance_variable_filter_patterns = [ /secret/ ]

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "PaymentService",
          :@secret_key => "sk-live-abc123",
          :@amount => 100
        })

        described_class.call(exc, context)
        parsed = JSON.parse(RailsErrorDashboard::ErrorLog.last.read_attribute(:instance_variables))

        expect(parsed["@secret_key"]["value"]).to eq("[FILTERED]")
        expect(parsed["@secret_key"]["filtered"]).to be true
        expect(parsed["@amount"]["value"]).to eq(100)
      ensure
        RailsErrorDashboard.configuration.instance_variable_filter_patterns = []
      end

      it "passes instance_variable_max_count to VariableSerializer" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")

        RailsErrorDashboard.configuration.instance_variable_max_count = 7

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "Foo",
          :@a => 1
        })

        expect(RailsErrorDashboard::Services::VariableSerializer).to receive(:call).with(
          anything,
          hash_including(max_count: 7)
        ).and_call_original

        described_class.call(exc, context)
      ensure
        RailsErrorDashboard.configuration.instance_variable_max_count = 20
      end

      it "captures both local and instance variables simultaneously" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")

        RailsErrorDashboard.configuration.enable_local_variables = true

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { name: "Gandalf", age: 2019 })
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "UsersController",
          :@current_user => "User#1"
        })

        described_class.call(exc, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        locals_parsed = JSON.parse(error_log.read_attribute(:local_variables))
        ivars_parsed = JSON.parse(error_log.read_attribute(:instance_variables))

        expect(locals_parsed["name"]["value"]).to eq("Gandalf")
        expect(ivars_parsed["@current_user"]["value"]).to eq("User#1")
      ensure
        RailsErrorDashboard.configuration.enable_local_variables = false
      end

      it "still creates error log when VariableSerializer fails" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "Foo",
          :@data => "test"
        })

        allow(RailsErrorDashboard::Services::VariableSerializer).to receive(:call)
          .and_raise(RuntimeError, "serializer boom")

        # Serialization failure is isolated — error log is still created
        expect {
          described_class.call(exc, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.read_attribute(:instance_variables)).to be_nil
      end

      it "still captures instance variables when local variable serialization fails" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")

        RailsErrorDashboard.configuration.enable_local_variables = true

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { data: "test" })
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "Foo",
          :@name => "Gandalf"
        })

        # Only fail on the first call (local vars) — let instance vars succeed
        call_count = 0
        allow(RailsErrorDashboard::Services::VariableSerializer).to receive(:call).and_wrap_original do |method, *args, **kwargs|
          call_count += 1
          raise RuntimeError, "local var boom" if call_count == 1
          method.call(*args, **kwargs)
        end

        expect {
          described_class.call(exc, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.read_attribute(:local_variables)).to be_nil
        expect(error_log.read_attribute(:instance_variables)).to be_present
        parsed = JSON.parse(error_log.read_attribute(:instance_variables))
        expect(parsed["@name"]["value"]).to eq("Gandalf")
      ensure
        RailsErrorDashboard.configuration.enable_local_variables = false
      end

      it "creates error log when both variable serializers fail" do
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("instance_variables")
        skip "column not present" unless RailsErrorDashboard::ErrorLog.column_names.include?("local_variables")

        RailsErrorDashboard.configuration.enable_local_variables = true

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { data: "test" })
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "Foo",
          :@data => "test"
        })

        allow(RailsErrorDashboard::Services::VariableSerializer).to receive(:call)
          .and_raise(RuntimeError, "serializer boom")

        expect {
          described_class.call(exc, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.read_attribute(:local_variables)).to be_nil
        expect(error_log.read_attribute(:instance_variables)).to be_nil
      ensure
        RailsErrorDashboard.configuration.enable_local_variables = false
      end
    end

    context "async path rescue isolation" do
      before do
        RailsErrorDashboard.configuration.async_logging = true
        RailsErrorDashboard.configuration.enable_instance_variables = true
        RailsErrorDashboard.configuration.filter_sensitive_data = true
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!
      end

      after do
        RailsErrorDashboard.configuration.async_logging = false
        RailsErrorDashboard.configuration.enable_instance_variables = false
        RailsErrorDashboard.configuration.enable_local_variables = false
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!
      end

      it "still enqueues job when instance variable serialization raises" do
        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "Foo",
          :@data => "test"
        })

        allow(RailsErrorDashboard::Services::VariableSerializer).to receive(:call)
          .and_raise(RuntimeError, "serializer boom")

        expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later) do |exception_data, ctx|
          expect(exception_data[:class_name]).to eq("StandardError")
          expect(ctx).not_to have_key(:_serialized_instance_variables)
        end

        described_class.call(exc, {})
      end

      it "still enqueues job when local variable serialization raises" do
        RailsErrorDashboard.configuration.enable_local_variables = true

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { data: "test" })

        allow(RailsErrorDashboard::Services::VariableSerializer).to receive(:call)
          .and_raise(RuntimeError, "serializer boom")

        expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later) do |exception_data, ctx|
          expect(exception_data[:class_name]).to eq("StandardError")
          expect(ctx).not_to have_key(:_serialized_local_variables)
        end

        described_class.call(exc, {})
      end

      it "still enqueues job when both variable serializers raise" do
        RailsErrorDashboard.configuration.enable_local_variables = true

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { data: "test" })
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "Foo",
          :@data => "test"
        })

        allow(RailsErrorDashboard::Services::VariableSerializer).to receive(:call)
          .and_raise(RuntimeError, "serializer boom")

        expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later) do |exception_data, ctx|
          expect(ctx).not_to have_key(:_serialized_local_variables)
          expect(ctx).not_to have_key(:_serialized_instance_variables)
        end

        described_class.call(exc, {})
      end

      it "includes serialized instance vars in async context on success" do
        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "UsersController",
          :@name => "Gandalf"
        })

        expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later) do |exception_data, ctx|
          expect(ctx).to have_key(:_serialized_instance_variables)
          ivars = ctx[:_serialized_instance_variables]
          expect(ivars["_self_class"][:value]).to eq("UsersController")
          expect(ivars["@name"][:value]).to eq("Gandalf")
        end

        described_class.call(exc, {})
      end

      it "includes serialized local vars in async context on success" do
        RailsErrorDashboard.configuration.enable_local_variables = true

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { wizard: "Gandalf", level: 99 })

        expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later) do |_exception_data, ctx|
          expect(ctx).to have_key(:_serialized_local_variables)
          locals = ctx[:_serialized_local_variables]
          expect(locals["wizard"][:value]).to eq("Gandalf")
          expect(locals["level"][:value]).to eq(99)
        end

        described_class.call(exc, {})
      end

      it "still enqueues job when LocalVariableCapturer.extract raises" do
        RailsErrorDashboard.configuration.enable_local_variables = true

        allow(RailsErrorDashboard::Services::LocalVariableCapturer).to receive(:extract)
          .and_raise(RuntimeError, "extractor boom")

        expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later) do |exception_data, ctx|
          expect(exception_data[:class_name]).to eq("StandardError")
          expect(ctx).not_to have_key(:_serialized_local_variables)
        end

        described_class.call(exception, {})
      end

      it "still enqueues job when LocalVariableCapturer.extract_instance_vars raises" do
        allow(RailsErrorDashboard::Services::LocalVariableCapturer).to receive(:extract_instance_vars)
          .and_raise(RuntimeError, "extractor boom")

        expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later) do |exception_data, ctx|
          expect(exception_data[:class_name]).to eq("StandardError")
          expect(ctx).not_to have_key(:_serialized_instance_variables)
        end

        described_class.call(exception, {})
      end

      it "captures instance vars when local var serialization fails in async path" do
        RailsErrorDashboard.configuration.enable_local_variables = true

        exc = StandardError.new("test")
        exc.instance_variable_set(:@_red_locals, { data: "test" })
        exc.instance_variable_set(:@_red_instance_vars, {
          _self_class: "Foo",
          :@name => "Gandalf"
        })

        # Only fail on the first call (local vars) — let instance vars succeed
        call_count = 0
        allow(RailsErrorDashboard::Services::VariableSerializer).to receive(:call).and_wrap_original do |method, *args, **kwargs|
          call_count += 1
          raise RuntimeError, "local var boom" if call_count == 1
          method.call(*args, **kwargs)
        end

        expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later) do |_exception_data, ctx|
          expect(ctx).not_to have_key(:_serialized_local_variables)
          expect(ctx).to have_key(:_serialized_instance_variables)
          expect(ctx[:_serialized_instance_variables]["@name"][:value]).to eq("Gandalf")
        end

        described_class.call(exc, {})
      end
    end
  end
end
