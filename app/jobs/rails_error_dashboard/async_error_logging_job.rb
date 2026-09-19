# frozen_string_literal: true

module RailsErrorDashboard
  # Background job for asynchronous error logging
  # This prevents error logging from blocking the main request/response cycle
  class AsyncErrorLoggingJob < ApplicationJob
    queue_as :default

    # Performs async error logging
    # @param exception_data [Hash] Serialized exception data
    # @param context [Hash] Error context (request, user, etc.)
    def perform(exception_data, context)
      # Normalize string keys (ActiveJob may deserialize with string keys)
      exception_data = exception_data.symbolize_keys if exception_data.respond_to?(:symbolize_keys)
      context = context.symbolize_keys if context.respond_to?(:symbolize_keys)

      # Reconstruct the exception from serialized data
      exception = reconstruct_exception(exception_data)

      # Pass pre-extracted cause chain via context so LogError can use it
      # (reconstructed exceptions don't have Ruby's built-in cause set)
      if exception_data[:cause_chain]
        context[:_serialized_cause_chain] = exception_data[:cause_chain]
      end

      # The type as REPORTED, independent of whether a Ruby class of that name
      # exists here. reconstruct_exception falls back to StandardError for an
      # unconstantizable name -- which is the normal case for a frontend or
      # mobile report -- and reading error_type off the reconstructed object
      # then renamed every such error StandardError, collapsing distinct
      # client errors into one group.
      if exception_data[:class_name].present?
        context[:_reported_error_type] = exception_data[:class_name]
      end

      # Log the error synchronously in the background job.
      # .new(...).call bypasses the async check (we're already async);
      # worker: true makes an unreachable error store raise instead of being
      # swallowed, so this job fails and retries rather than acknowledging a
      # capture it never wrote.
      Commands::LogError.new(exception, context, worker: true).call
    rescue *Commands::LogError::RETRYABLE_STORE_ERRORS => e
      # The error database is unreachable. Protecting a user request and
      # deciding whether a background job succeeded are different contracts:
      # swallowing here told Active Job the capture was delivered when nothing
      # was written, so the payload was gone for good. Let it fail instead and
      # let retry_on schedule another attempt.
      #
      # Rails reports this job failure to Rails.error, so RED will try to
      # capture it too; that capture fails the same way and is swallowed by
      # LogError's own rescue. ErrorReporter's recursion guard (issue #114)
      # plus the attempt cap bound this to a few wasted attempts, not a loop.
      Rails.logger.error("AsyncErrorLoggingJob: error storage unavailable (#{e.class}: #{e.message}) — will retry")
      raise
    rescue => e
      # A payload problem (unparseable arguments, a class that cannot be
      # reconstructed). Retrying replays the identical payload, so it would
      # fail identically three times and still be discarded. Log and drop.
      Rails.logger.error("AsyncErrorLoggingJob failed: #{e.message}")
      Rails.logger.error("Backtrace: #{e.backtrace&.first(5)&.join("\n")}")
    end

    private

    # Reconstruct exception from serialized data
    # @param data [Hash] Serialized exception data
    # @return [Exception] Reconstructed exception object
    #
    # Never relies on the subclass constructor: many real exception classes
    # take something other than a message (ActiveRecord::RecordInvalid wants
    # the record, custom errors take keywords), and `Klass.new(message)` on
    # those raised inside the job, which rescued it and dropped the capture.
    # Allocate the right class so error_type/fingerprint stay correct, then
    # set the message with Exception's own initializer, bypassing whatever
    # the subclass expects. Fall back to the constructor for classes whose
    # `message` needs state their initializer sets.
    def reconstruct_exception(data)
      exception_class = begin
        data[:class_name].constantize
      rescue NameError
        # If class doesn't exist, use StandardError
        StandardError
      end

      exception = allocate_exception(exception_class, data[:message]) ||
                  construct_exception(exception_class, data[:message]) ||
                  StandardError.new(data[:message])

      # Restore the backtrace
      exception.set_backtrace(data[:backtrace]) if data[:backtrace]

      exception
    end

    def allocate_exception(exception_class, message)
      return nil unless exception_class < Exception

      exception = exception_class.allocate
      Exception.instance_method(:initialize).bind_call(exception, message)
      exception.message # a subclass `message` that needs constructor state raises here
      exception
    rescue StandardError, NoMemoryError
      nil
    end

    def construct_exception(exception_class, message)
      exception = exception_class.new(message)
      exception.message
      exception
    rescue StandardError
      nil
    end
  end
end
