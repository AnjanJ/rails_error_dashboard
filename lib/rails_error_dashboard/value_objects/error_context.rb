# frozen_string_literal: true

module RailsErrorDashboard
  module ValueObjects
    # Immutable value object representing error context
    # Extracts and normalizes context information from various sources
    class ErrorContext
      attr_reader :user_id, :request_url, :request_params, :user_agent, :ip_address, :platform,
                  :controller_name, :action_name, :request_id, :session_id,
                  :http_method, :hostname, :content_type, :request_duration_ms

      def initialize(context, source = nil)
        @context = context
        @source = source

        @user_id = extract_user_id
        @request_url = build_request_url
        @request_params = extract_params
        @user_agent = extract_user_agent
        @ip_address = extract_ip_address
        @platform = detect_platform
        @controller_name = extract_controller_name
        @action_name = extract_action_name
        @request_id = extract_request_id
        @session_id = extract_session_id
        @http_method = extract_http_method
        @hostname = extract_hostname
        @content_type = extract_content_type
        @request_duration_ms = extract_request_duration_ms
      end

      def to_h
        {
          user_id: user_id,
          request_url: request_url,
          request_params: request_params,
          user_agent: user_agent,
          ip_address: ip_address,
          platform: platform,
          controller_name: controller_name,
          action_name: action_name,
          http_method: http_method,
          hostname: hostname,
          content_type: content_type,
          request_duration_ms: request_duration_ms
        }
      end

      private

      def extract_user_id
        @context[:current_user]&.id ||
          @context[:user_id] ||
          @context[:user]&.id
      end

      def build_request_url
        # Handle both full Rails requests and API-only requests
        if @context[:request]
          begin
            return @context[:request].fullpath
          rescue NoMethodError
            # Fallback for minimal request objects
            return @context[:request].path rescue nil
          end
        end

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
        # If platform is explicitly provided in context, use it
        return @context[:platform] if @context[:platform].present?

        # Check if it's from a mobile request
        user_agent = extract_user_agent

        return "API" unless user_agent.present? && @context[:request]

        # Only detect platform if we have a valid user agent
        begin
          Services::PlatformDetector.detect(user_agent)
        rescue => e
          # Fallback to API if platform detection fails
          Rails.logger.debug("[RailsErrorDashboard] Platform detection failed: #{e.message}")
          "API"
        end
      end

      def extract_controller_name
        # From Rails request params
        return @context[:request].params[:controller] if @context[:request]&.params&.[](:controller)

        # From explicit context
        return @context[:controller_name] if @context[:controller_name]

        # From Rails controller instance
        return @context[:controller]&.class&.name if @context[:controller]

        nil
      end

      def extract_action_name
        # From Rails request params
        return @context[:request].params[:action] if @context[:request]&.params&.[](:action)

        # From explicit context
        return @context[:action_name] if @context[:action_name]

        # From action parameter
        return @context[:action] if @context[:action]

        nil
      end

      def extract_request_id
        # From Rails request
        return @context[:request]&.request_id if @context[:request]&.respond_to?(:request_id)

        # From explicit context
        return @context[:request_id] if @context[:request_id]

        # From job ID (for background jobs)
        return @context[:job]&.job_id if @context[:job]
        return @context[:jid] if @context[:jid]

        nil
      end

      def extract_session_id
        # Session is only available in full Rails mode, not API-only
        return @context[:request]&.session&.id if @context[:request]&.respond_to?(:session) && @context[:request]&.session

        # From explicit context
        return @context[:session_id] if @context[:session_id]

        nil
      end

      def extract_http_method
        return @context[:request]&.method if @context[:request]&.respond_to?(:method)
        return @context[:http_method] if @context[:http_method]

        nil
      end

      def extract_hostname
        return @context[:request]&.host if @context[:request]&.respond_to?(:host)
        return @context[:hostname] if @context[:hostname]

        nil
      end

      def extract_content_type
        if @context[:request]&.respond_to?(:content_type)
          ct = @context[:request].content_type
          # content_type can return a MIME::Type object or string depending on Rails version
          return ct.to_s.presence
        end

        return @context[:content_type] if @context[:content_type]

        nil
      end

      def extract_request_duration_ms
        # Duration is calculated from the start time stored in the Rack env
        if @context[:request]&.respond_to?(:env)
          start_time = @context[:request].env["rails_error_dashboard.request_start"]
          if start_time
            elapsed = (Time.now.to_f - start_time.to_f) * 1000
            return elapsed.round
          end
        end

        return @context[:request_duration_ms] if @context[:request_duration_ms]

        nil
      end
    end
  end
end
