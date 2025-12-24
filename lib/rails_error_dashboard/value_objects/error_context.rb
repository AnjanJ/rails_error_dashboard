# frozen_string_literal: true

module RailsErrorDashboard
  module ValueObjects
    # Immutable value object representing error context
    # Extracts and normalizes context information from various sources
    class ErrorContext
      attr_reader :user_id, :request_url, :request_params, :user_agent, :ip_address, :platform

      def initialize(context, source = nil)
        @context = context
        @source = source

        @user_id = extract_user_id
        @request_url = build_request_url
        @request_params = extract_params
        @user_agent = extract_user_agent
        @ip_address = extract_ip_address
        @platform = detect_platform
      end

      def to_h
        {
          user_id: user_id,
          request_url: request_url,
          request_params: request_params,
          user_agent: user_agent,
          ip_address: ip_address,
          platform: platform
        }
      end

      private

      def extract_user_id
        @context[:current_user]&.id ||
          @context[:user_id] ||
          @context[:user]&.id
      end

      def build_request_url
        return @context[:request]&.fullpath if @context[:request]
        return @context[:request_url] if @context[:request_url]
        return "Background Job: #{@context[:job]&.class}" if @context[:job]
        return "Sidekiq: #{@context[:job_class]}" if @context[:job_class]
        return "Service: #{@context[:service]}" if @context[:service]
        return @source if @source

        "Rails Application"
      end

      def extract_params
        params = {}

        # HTTP request params
        if @context[:request]
          params = @context[:request].params.except(:controller, :action)
        end

        # Background job params
        if @context[:job]
          params = {
            job_class: @context[:job].class.name,
            job_id: @context[:job].job_id,
            queue: @context[:job].queue_name,
            arguments: @context[:job].arguments,
            executions: @context[:job].executions
          }
        end

        # Sidekiq params
        if @context[:job_class]
          params = {
            job_class: @context[:job_class],
            job_id: @context[:jid],
            queue: @context[:queue],
            retry_count: @context[:retry_count]
          }
        end

        # Custom params
        params.merge!(@context[:params]) if @context[:params]

        # Additional context (from mobile apps, etc.)
        params.merge!(@context[:additional_context]) if @context[:additional_context]

        params.to_json
      end

      def extract_user_agent
        return @context[:request]&.user_agent if @context[:request]
        return "Sidekiq Worker" if @source&.to_s&.include?("active_job") || @context[:job]
        return @context[:user_agent] if @context[:user_agent]

        "Rails Application"
      end

      def extract_ip_address
        return @context[:request]&.remote_ip if @context[:request]
        return "background_job" if @context[:job]
        return "sidekiq_worker" if @context[:job_class]
        return @context[:ip_address] if @context[:ip_address]

        "application_layer"
      end

      def detect_platform
        # Check if it's from a mobile request
        user_agent = extract_user_agent
        return Services::PlatformDetector.detect(user_agent) if @context[:request]

        # Everything else is API/backend
        "API"
      end
    end
  end
end
