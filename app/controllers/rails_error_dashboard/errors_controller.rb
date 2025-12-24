# frozen_string_literal: true

module RailsErrorDashboard
  class ErrorsController < ApplicationController
    include Pagy::Backend

    before_action :authenticate_dashboard_user!

    def index
      # Use Query to get filtered errors
      errors_query = Queries::ErrorsList.call(filter_params)

      # Paginate with Pagy
      @pagy, @errors = pagy(errors_query, items: params[:per_page] || 25)

      # Get dashboard stats using Query
      @stats = Queries::DashboardStats.call

      # Get filter options using Query
      filter_options = Queries::FilterOptions.call
      @environments = filter_options[:environments]
      @error_types = filter_options[:error_types]
      @platforms = filter_options[:platforms]
    end

    def show
      @error = ErrorLog.find(params[:id])
      @related_errors = @error.related_errors(limit: 5)
    end

    def resolve
      # Use Command to resolve error
      @error = Commands::ResolveError.call(
        params[:id],
        resolved_by_name: params[:resolved_by_name],
        resolution_comment: params[:resolution_comment],
        resolution_reference: params[:resolution_reference]
      )

      redirect_to error_path(@error)
    end

    def analytics
      days = (params[:days] || 30).to_i
      @days = days

      # Use Query to get analytics data
      analytics = Queries::AnalyticsStats.call(days)

      @error_stats = analytics[:error_stats]
      @errors_over_time = analytics[:errors_over_time]
      @errors_by_type = analytics[:errors_by_type]
      @errors_by_platform = analytics[:errors_by_platform]
      @errors_by_environment = analytics[:errors_by_environment]
      @errors_by_hour = analytics[:errors_by_hour]
      @top_users = analytics[:top_users]
      @resolution_rate = analytics[:resolution_rate]
      @mobile_errors = analytics[:mobile_errors]
      @api_errors = analytics[:api_errors]
    end

    private

    def filter_params
      {
        environment: params[:environment],
        error_type: params[:error_type],
        unresolved: params[:unresolved],
        platform: params[:platform],
        search: params[:search]
      }
    end

    def authenticate_dashboard_user!
      return if skip_authentication?

      authenticate_or_request_with_http_basic do |username, password|
        ActiveSupport::SecurityUtils.secure_compare(
          username,
          RailsErrorDashboard.configuration.dashboard_username
        ) &
        ActiveSupport::SecurityUtils.secure_compare(
          password,
          RailsErrorDashboard.configuration.dashboard_password
        )
      end
    end

    def skip_authentication?
      !RailsErrorDashboard.configuration.require_authentication ||
        (Rails.env.development? && !RailsErrorDashboard.configuration.require_authentication_in_development)
    end
  end
end
