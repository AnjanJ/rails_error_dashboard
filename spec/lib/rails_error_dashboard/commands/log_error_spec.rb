# frozen_string_literal: true

require "rails_helper"

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

  # Helper to create unique exceptions with different backtraces
  def create_unique_exception(klass, message, index = 0)
    error = klass.new(message)
    # Set a unique backtrace so deduplication doesn't kick in
    # Vary both file AND line to ensure truly unique errors
    error.set_backtrace([ "#{Rails.root}/app/controllers/test_#{index}_controller.rb:#{index + 10}:in `action#{index}'" ])
    error
  end

  describe ".call" do
    let(:exception) { StandardError.new("Test error") }
    let(:context) { {} }

    describe "ignored exceptions" do
      after do
        RailsErrorDashboard.reset_configuration!
      end

      context "when exception class is in ignored_exceptions list" do
        before do
          RailsErrorDashboard.configure do |config|
            config.ignored_exceptions = [ "ActionController::RoutingError" ]
          end
        end

        it "does not create error log for ignored exception" do
          routing_error = ActionController::RoutingError.new("No route")

          expect {
            described_class.call(routing_error, context)
          }.not_to change(RailsErrorDashboard::ErrorLog, :count)
        end

        it "returns nil for ignored exception" do
          routing_error = ActionController::RoutingError.new("No route")
          result = described_class.call(routing_error, context)

          expect(result).to be_nil
        end

        it "creates error log for non-ignored exception" do
          standard_error = StandardError.new("Not ignored")

          expect {
            described_class.call(standard_error, context)
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
        end
      end

      context "with regex patterns in ignored_exceptions" do
        before do
          RailsErrorDashboard.configure do |config|
            config.ignored_exceptions = [ /Custom.*Error/ ]
          end
        end

        it "ignores exceptions matching regex pattern" do
          # Create a custom error class
          custom_error_class = Class.new(StandardError)
          stub_const("CustomPaymentError", custom_error_class)

          custom_error = CustomPaymentError.new("Payment failed")

          expect {
            described_class.call(custom_error, context)
          }.not_to change(RailsErrorDashboard::ErrorLog, :count)
        end

        it "does not ignore exceptions not matching regex" do
          standard_error = StandardError.new("Not matching")

          expect {
            described_class.call(standard_error, context)
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
        end

        it "ignores multiple custom errors matching pattern" do
          validation_class = Class.new(StandardError)
          payment_class = Class.new(StandardError)
          stub_const("CustomValidationError", validation_class)
          stub_const("CustomPaymentError", payment_class)

          validation_error = CustomValidationError.new("Validation failed")
          payment_error = CustomPaymentError.new("Payment failed")

          expect {
            described_class.call(validation_error, context)
            described_class.call(payment_error, context)
          }.not_to change(RailsErrorDashboard::ErrorLog, :count)
        end
      end

      context "with multiple ignored exceptions" do
        before do
          RailsErrorDashboard.configure do |config|
            config.ignored_exceptions = [
              "ActionController::RoutingError",
              "ActiveRecord::RecordNotFound",
              /Timeout.*Error/
            ]
          end
        end

        it "ignores all configured exception types" do
          routing_error = ActionController::RoutingError.new("No route")
          not_found_error = ActiveRecord::RecordNotFound.new("Not found")

          timeout_class = Class.new(StandardError)
          stub_const("TimeoutError", timeout_class)
          timeout_error = TimeoutError.new("Timeout")

          expect {
            described_class.call(routing_error, context)
            described_class.call(not_found_error, context)
            described_class.call(timeout_error, context)
          }.not_to change(RailsErrorDashboard::ErrorLog, :count)
        end
      end

      context "with empty ignored_exceptions" do
        before do
          RailsErrorDashboard.configure do |config|
            config.ignored_exceptions = []
          end
        end

        it "logs all exceptions" do
          expect {
            described_class.call(exception, context)
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
        end
      end

      context "with invalid class name in ignored_exceptions" do
        before do
          RailsErrorDashboard.configure do |config|
            config.ignored_exceptions = [ "NonExistentError" ]
          end
        end

        it "logs warning and continues" do
          expect(RailsErrorDashboard::Logger).to receive(:warn).with(/Invalid ignored exception class/)

          expect {
            described_class.call(exception, context)
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
        end
      end

      context "with exception inheritance" do
        before do
          RailsErrorDashboard.configure do |config|
            config.ignored_exceptions = [ "StandardError" ]
          end
        end

        it "ignores subclasses of ignored exception" do
          # ArgumentError inherits from StandardError
          arg_error = ArgumentError.new("Bad argument")

          expect {
            described_class.call(arg_error, context)
          }.not_to change(RailsErrorDashboard::ErrorLog, :count)
        end

        it "ignores the configured exception itself" do
          standard_error = StandardError.new("Error")

          expect {
            described_class.call(standard_error, context)
          }.not_to change(RailsErrorDashboard::ErrorLog, :count)
        end
      end
    end

    context "without ignored exceptions configuration" do
      it "logs exception normally" do
        expect {
          described_class.call(exception, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end
    end

    describe "error sampling" do
      after do
        RailsErrorDashboard.reset_configuration!
      end

      context "with 100% sampling rate (default)" do
        before do
          RailsErrorDashboard.configure do |config|
            config.sampling_rate = 1.0
          end
        end

        it "logs all errors" do
          expect {
            10.times { |i| described_class.call(create_unique_exception(StandardError, "Error", i), context) }
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(10)
        end
      end

      context "with 0% sampling rate" do
        before do
          RailsErrorDashboard.configure do |config|
            config.sampling_rate = 0.0
          end
        end

        it "does not log non-critical errors" do
          expect {
            10.times { |i| described_class.call(create_unique_exception(StandardError, "Error", i), context) }
          }.not_to change(RailsErrorDashboard::ErrorLog, :count)
        end

        it "still logs critical errors" do
          expect {
            10.times { |i| described_class.call(create_unique_exception(SecurityError, "Security breach", i), context) }
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(10)
        end
      end

      context "with 50% sampling rate" do
        before do
          RailsErrorDashboard.configure do |config|
            config.sampling_rate = 0.5
          end
        end

        it "logs approximately 50% of non-critical errors (probabilistic)" do
          # With 50% sampling, we expect around 50% of errors to be logged
          # Over 100 errors, we should see between 35-65 logged (allowing for randomness)
          srand(12345) # Seed for reproducible results

          count_before = RailsErrorDashboard::ErrorLog.count
          100.times { |i| described_class.call(create_unique_exception(StandardError, "Error", i), context) }
          count_after = RailsErrorDashboard::ErrorLog.count
          logged_count = count_after - count_before

          expect(logged_count).to be_between(35, 65)
        end
      end

      context "with 10% sampling rate" do
        before do
          RailsErrorDashboard.configure do |config|
            config.sampling_rate = 0.1
          end
        end

        it "logs approximately 10% of non-critical errors (probabilistic)" do
          # With 10% sampling, we expect around 10% of errors to be logged
          # Over 100 errors, we should see between 3-17 logged (allowing for randomness)
          srand(54321) # Seed for reproducible results

          count_before = RailsErrorDashboard::ErrorLog.count
          100.times { |i| described_class.call(create_unique_exception(StandardError, "Error", i), context) }
          count_after = RailsErrorDashboard::ErrorLog.count
          logged_count = count_after - count_before

          expect(logged_count).to be_between(3, 17)
        end
      end

      context "critical errors bypass sampling" do
        before do
          RailsErrorDashboard.configure do |config|
            config.sampling_rate = 0.1 # Very low sampling
          end
        end

        it "always logs SecurityError regardless of sampling" do
          expect {
            10.times { |i| described_class.call(create_unique_exception(SecurityError, "Security issue", i), context) }
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(10)
        end

        it "always logs NoMemoryError regardless of sampling" do
          expect {
            10.times { |i| described_class.call(create_unique_exception(NoMemoryError, "Out of memory", i), context) }
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(10)
        end

        it "always logs SystemStackError regardless of sampling" do
          expect {
            10.times { |i| described_class.call(create_unique_exception(SystemStackError, "Stack overflow", i), context) }
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(10)
        end

        it "always logs ActiveRecord::StatementInvalid regardless of sampling" do
          expect {
            10.times { |i| described_class.call(create_unique_exception(ActiveRecord::StatementInvalid, "Bad SQL", i), context) }
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(10)
        end
      end

      context "with mixed error types and low sampling" do
        before do
          RailsErrorDashboard.configure do |config|
            config.sampling_rate = 0.0 # Skip all non-critical
          end
        end

        it "logs all critical errors but skips non-critical" do
          # Log 3 critical and 3 non-critical
          3.times do |i|
            described_class.call(create_unique_exception(SecurityError, "Critical", i), context)
          end

          3.times do |i|
            described_class.call(create_unique_exception(StandardError, "Non-critical", i + 10), context)
          end

          # Should only have 3 critical errors logged
          expect(RailsErrorDashboard::ErrorLog.count).to eq(3)
          expect(RailsErrorDashboard::ErrorLog.where(error_type: "SecurityError").count).to eq(3)
          expect(RailsErrorDashboard::ErrorLog.where(error_type: "StandardError").count).to eq(0)
        end
      end

      context "with sampling rate > 1.0" do
        before do
          RailsErrorDashboard.configure do |config|
            config.sampling_rate = 1.5 # Invalid but treated as 100%
          end
        end

        it "logs all errors (treats as 100%)" do
          expect {
            10.times { |i| described_class.call(create_unique_exception(StandardError, "Error", i), context) }
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(10)
        end
      end

      context "with negative sampling rate" do
        before do
          RailsErrorDashboard.configure do |config|
            config.sampling_rate = -0.5 # Invalid
          end
        end

        it "does not log non-critical errors" do
          expect {
            10.times { |i| described_class.call(create_unique_exception(StandardError, "Error", i), context) }
          }.not_to change(RailsErrorDashboard::ErrorLog, :count)
        end

        it "still logs critical errors" do
          expect {
            10.times { |i| described_class.call(create_unique_exception(SecurityError, "Critical", i), context) }
          }.to change(RailsErrorDashboard::ErrorLog, :count).by(10)
        end
      end
    end

    describe "exception cause chain capture" do
      context "when exception has a cause" do
        it "stores the cause chain as JSON" do
          error = begin
            begin
              raise ArgumentError, "original problem"
            rescue
              raise StandardError, "wrapper error"
            end
          rescue => e
            e
          end

          result = described_class.call(error, context)

          expect(result).to be_present
          expect(result.exception_cause).to be_present

          parsed = JSON.parse(result.exception_cause)
          expect(parsed).to be_an(Array)
          expect(parsed.length).to eq(1)
          expect(parsed[0]["class_name"]).to eq("ArgumentError")
          expect(parsed[0]["message"]).to eq("original problem")
        end
      end

      context "when exception has no cause" do
        it "stores nil for exception_cause" do
          error = StandardError.new("simple error")

          result = described_class.call(error, context)

          expect(result).to be_present
          expect(result.exception_cause).to be_nil
        end
      end

      context "when exception has a multi-level cause chain" do
        it "captures the full chain" do
          error = begin
            begin
              begin
                raise RuntimeError, "root cause"
              rescue
                raise IOError, "middle error"
              end
            rescue
              raise StandardError, "top error"
            end
          rescue => e
            e
          end

          result = described_class.call(error, context)

          parsed = JSON.parse(result.exception_cause)
          expect(parsed.length).to eq(2)
          expect(parsed[0]["class_name"]).to eq("IOError")
          expect(parsed[1]["class_name"]).to eq("RuntimeError")
        end
      end
    end

    # Phase 4.3: Baseline Alert Integration Tests
    describe "baseline alert integration" do
      let(:exception) { create_unique_exception(StandardError, "Test error", 0) }

      before do
        # Clear throttler cache
        RailsErrorDashboard::Services::BaselineAlertThrottler.clear!

        # Reset configuration
        RailsErrorDashboard.reset_configuration!
      end

      after do
        RailsErrorDashboard.reset_configuration!
      end

      context "when baseline alerts are disabled" do
        before do
          RailsErrorDashboard.configure do |config|
            config.enable_baseline_alerts = false
          end
        end

        it "does not check for baseline anomalies" do
          expect(RailsErrorDashboard::BaselineAlertJob).not_to receive(:perform_later)
          described_class.call(exception, context)
        end
      end

      context "when baseline alerts are enabled" do
        before do
          RailsErrorDashboard.configure do |config|
            config.enable_baseline_alerts = true
            config.baseline_alert_threshold_std_devs = 2.0
            config.baseline_alert_severities = [ :critical, :high ]
          end
        end

        context "when no baseline exists" do
          it "does not queue alert job" do
            expect(RailsErrorDashboard::BaselineAlertJob).not_to receive(:perform_later)
            described_class.call(exception, context)
          end
        end

        context "when baseline exists and anomaly detected" do
          before do
            # Stub the baseline_anomaly method to return an anomaly
            allow_any_instance_of(RailsErrorDashboard::ErrorLog).to receive(:baseline_anomaly).and_return({
              anomaly: true,
              level: :high,
              baseline_type: "hourly",
              threshold: 4.0,
              std_devs_above: 3.0
            })
          end

          it "queues baseline alert job with anomaly data" do
            expect(RailsErrorDashboard::BaselineAlertJob).to receive(:perform_later) do |error_log_id, anomaly_data|
              expect(error_log_id).to be_present
              expect(anomaly_data[:anomaly]).to be true
              expect(anomaly_data[:level]).to eq(:high)
            end

            described_class.call(exception, context)
          end

          it "logs alert queued message" do
            # Allow other logging calls that may occur during the process
            allow(RailsErrorDashboard::Logger).to receive(:info).and_call_original
            expect(RailsErrorDashboard::Logger).to receive(:info).with(/Baseline alert queued/).and_call_original
            described_class.call(exception, context)
          end

          context "when anomaly level is not in alert severities" do
            before do
              RailsErrorDashboard.configure do |config|
                config.baseline_alert_severities = [ :critical ] # Only critical
              end

              # Stub with elevated anomaly (not in alert severities)
              allow_any_instance_of(RailsErrorDashboard::ErrorLog).to receive(:baseline_anomaly).and_return({
                anomaly: true,
                level: :elevated, # Not in [:critical]
                baseline_type: "hourly",
                threshold: 4.0,
                std_devs_above: 2.1
              })
            end

            it "does not queue alert job" do
              expect(RailsErrorDashboard::BaselineAlertJob).not_to receive(:perform_later)
              described_class.call(exception, context)
            end
          end
        end

        context "when baseline exists but no anomaly" do
          let!(:baseline) do
            RailsErrorDashboard::ErrorBaseline.create!(
              error_type: "StandardError",
              platform: "unknown",
              baseline_type: "hourly",
              period_start: 1.hour.ago,
              period_end: Time.current,
              count: 10,
              mean: 100.0, # High baseline
              std_dev: 10.0,
              percentile_95: 120.0,
              percentile_99: 130.0,
              sample_size: 100
            )
          end

          it "does not queue alert job" do
            expect(RailsErrorDashboard::BaselineAlertJob).not_to receive(:perform_later)
            described_class.call(exception, context)
          end
        end

        context "when baseline check fails" do
          before do
            allow_any_instance_of(RailsErrorDashboard::ErrorLog).to receive(:baseline_anomaly)
              .and_raise(StandardError.new("Database error"))
          end

          it "handles error gracefully" do
            expect(RailsErrorDashboard::Logger).to receive(:error).with(/Failed to check baseline anomaly/)

            expect {
              described_class.call(exception, context)
            }.not_to raise_error
          end

          it "still creates the error log" do
            expect {
              described_class.call(exception, context)
            }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
          end
        end

        context "with custom threshold" do
          before do
            RailsErrorDashboard.configure do |config|
              config.baseline_alert_threshold_std_devs = 3.0 # More strict
            end
          end

          let!(:baseline) do
            RailsErrorDashboard::ErrorBaseline.create!(
              error_type: "StandardError",
              platform: "unknown",
              baseline_type: "hourly",
              period_start: 1.hour.ago,
              period_end: Time.current,
              count: 10,
              mean: 5.0,
              std_dev: 1.0,
              percentile_95: 7.0,
              percentile_99: 8.0,
              sample_size: 100
            )
          end

          it "uses custom threshold for anomaly detection" do
            # Create errors just above 2.0 std devs but below 3.0 std devs
            # Threshold: 5.0 + (3.0 * 1.0) = 8.0
            # Create 7 errors (below threshold)
            6.times do |i|
              create(:error_log,
                error_type: "StandardError",
                platform: "unknown",
                occurred_at: Time.current.beginning_of_day + i.minutes)
            end

            # Should not trigger alert (below 3.0 std devs)
            expect(RailsErrorDashboard::BaselineAlertJob).not_to receive(:perform_later)
            described_class.call(exception, context)
          end
        end
      end

      context "when BaselineAlertJob is not defined" do
        before do
          RailsErrorDashboard.configure do |config|
            config.enable_baseline_alerts = true
          end

          # Stub the check to simulate missing constant
          allow_any_instance_of(described_class).to receive(:check_baseline_anomaly) do |_cmd, _error_log|
            # Simulate the constant check
            unless defined?(RailsErrorDashboard::BaselineAlertJob)
              return
            end
          end
        end

        it "does not raise error" do
          expect {
            described_class.call(exception, context)
          }.not_to raise_error
        end
      end
    end
  end
end
