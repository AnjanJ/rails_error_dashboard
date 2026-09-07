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

      # Log the error synchronously in the background job
      # Call .new().call to bypass async check (we're already async)
      Commands::LogError.new(exception, context).call
    rescue => e
      # Don't let async job errors break the job queue
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
