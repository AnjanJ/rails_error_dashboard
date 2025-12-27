# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ActiveSupport::Notifications Integration" do
  before do
    # Ensure async_logging is disabled for synchronous event testing
    RailsErrorDashboard.configure do |config|
      config.async_logging = false
    end
  end

  after do
    RailsErrorDashboard.reset_configuration!
  end

  describe "error_logged.rails_error_dashboard event" do
    it "is emitted when an error is logged" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = StandardError.new("Test error")
      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(events.size).to eq(1)
      event = events.first
      expect(event.payload[:error_log]).to eq(error_log)
      expect(event.payload[:error_id]).to eq(error_log.id)
      expect(event.payload[:error_type]).to eq("StandardError")
      expect(event.payload[:message]).to eq("Test error")

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "includes severity in payload" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = ArgumentError.new("Bad argument")
      RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(events.first.payload[:severity]).to eq(:high)

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "includes platform in payload" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = StandardError.new("Test error")
      RailsErrorDashboard::Commands::LogError.call(error, {})

      payload = events.first.payload
      expect(payload[:platform]).to eq("API")

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "includes occurred_at timestamp in payload" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = StandardError.new("Test error")
      RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(events.first.payload[:occurred_at]).to be_a(Time)

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "is not emitted on error recurrence" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = StandardError.new("Same error")
      error.set_backtrace([ "test.rb:1" ])

      # First occurrence
      RailsErrorDashboard::Commands::LogError.call(error, {})
      expect(events.size).to eq(1)

      # Second occurrence (should not emit)
      RailsErrorDashboard::Commands::LogError.call(error, {})
      expect(events.size).to eq(1) # Still 1, not 2

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "can be subscribed to with a block" do
      received_payload = nil
      subscriber = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |_name, _start, _finish, _id, payload|
        received_payload = payload
      end

      error = StandardError.new("Test error")
      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(received_payload).not_to be_nil
      expect(received_payload[:error_id]).to eq(error_log.id)

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  describe "critical_error.rails_error_dashboard event" do
    it "is emitted when a critical error is logged" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("critical_error.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = SecurityError.new("Security breach")
      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(events.size).to eq(1)
      expect(events.first.payload[:error_log]).to eq(error_log)
      expect(events.first.payload[:error_type]).to eq("SecurityError")

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "is not emitted for non-critical errors" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("critical_error.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = StandardError.new("Non-critical error")
      RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(events.size).to eq(0)

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "is emitted for all critical error types" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("critical_error.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      RailsErrorDashboard::Commands::LogError.call(SecurityError.new("Security"), {})
      RailsErrorDashboard::Commands::LogError.call(NoMemoryError.new("Memory"), {})
      RailsErrorDashboard::Commands::LogError.call(SystemStackError.new("Stack"), {})

      expect(events.size).to eq(3)
      expect(events.map { |e| e.payload[:error_type] }).to contain_exactly(
        "SecurityError", "NoMemoryError", "SystemStackError"
      )

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "includes same payload structure as error_logged event" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("critical_error.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = SecurityError.new("Critical")
      RailsErrorDashboard::Commands::LogError.call(error, {})

      payload = events.first.payload
      expect(payload.keys).to include(:error_log, :error_id, :error_type, :message, :severity, :platform, :occurred_at)

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  describe "error_resolved.rails_error_dashboard event" do
    it "is emitted when an error is resolved" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("error_resolved.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = StandardError.new("Test error")
      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})
      RailsErrorDashboard::Commands::ResolveError.call(error_log.id, { resolved_by_name: "Test User" })

      expect(events.size).to eq(1)
      expect(events.first.payload[:error_log]).to eq(error_log.reload)
      expect(events.first.payload[:error_id]).to eq(error_log.id)

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "includes error_type in payload" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("error_resolved.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = ArgumentError.new("Test error")
      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})
      RailsErrorDashboard::Commands::ResolveError.call(error_log.id)

      expect(events.first.payload[:error_type]).to eq("ArgumentError")

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "includes resolved_by in payload" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("error_resolved.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = StandardError.new("Test error")
      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})
      RailsErrorDashboard::Commands::ResolveError.call(error_log.id, { resolved_by_name: "Jane Doe" })

      expect(events.first.payload[:resolved_by]).to eq("Jane Doe")

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "includes resolved_at timestamp in payload" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("error_resolved.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      error = StandardError.new("Test error")
      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})
      RailsErrorDashboard::Commands::ResolveError.call(error_log.id)

      expect(events.first.payload[:resolved_at]).to be_a(Time)

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  describe "multiple subscribers" do
    it "allows multiple subscribers to the same event" do
      subscriber1_called = false
      subscriber2_called = false

      subscriber1 = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do
        subscriber1_called = true
      end

      subscriber2 = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do
        subscriber2_called = true
      end

      error = StandardError.new("Test error")
      RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(subscriber1_called).to be true
      expect(subscriber2_called).to be true

      ActiveSupport::Notifications.unsubscribe(subscriber1)
      ActiveSupport::Notifications.unsubscribe(subscriber2)
    end

    it "allows subscribing to multiple events" do
      error_logged_count = 0
      critical_error_count = 0
      resolved_count = 0

      sub1 = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do
        error_logged_count += 1
      end

      sub2 = ActiveSupport::Notifications.subscribe("critical_error.rails_error_dashboard") do
        critical_error_count += 1
      end

      sub3 = ActiveSupport::Notifications.subscribe("error_resolved.rails_error_dashboard") do
        resolved_count += 1
      end

      # Log non-critical error
      error1 = StandardError.new("Test")
      error_log1 = RailsErrorDashboard::Commands::LogError.call(error1, {})

      # Log critical error
      error2 = SecurityError.new("Critical")
      RailsErrorDashboard::Commands::LogError.call(error2, {})

      # Resolve an error
      RailsErrorDashboard::Commands::ResolveError.call(error_log1.id)

      expect(error_logged_count).to eq(2) # Both errors
      expect(critical_error_count).to eq(1) # Only critical
      expect(resolved_count).to eq(1) # One resolved

      ActiveSupport::Notifications.unsubscribe(sub1)
      ActiveSupport::Notifications.unsubscribe(sub2)
      ActiveSupport::Notifications.unsubscribe(sub3)
    end
  end

  describe "integration with other Rails instrumentation" do
    it "works alongside standard Rails error instrumentation" do
      our_events = []
      subscriber = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        our_events << event
      end

      error = StandardError.new("Test error")
      RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(our_events.size).to eq(1)

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end
end
