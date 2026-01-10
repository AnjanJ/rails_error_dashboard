# frozen_string_literal: true

module RailsErrorDashboard
  class ErrorsController < ApplicationController
    include Pagy::Backend

    before_action :authenticate_dashboard_user!

    FILTERABLE_PARAMS = %i[
      error_type
      unresolved
      platform
      application_id
      search
      severity
      timeframe
      frequency
      status
      assigned_to
      priority_level
      hide_snoozed
      sort_by
      sort_direction
    ].freeze

    def overview
      # Get dashboard stats using Query
      @stats = Queries::DashboardStats.call

      # Get platform health summary (if enabled)
      if RailsErrorDashboard.configuration.enable_platform_comparison
        comparison = Queries::PlatformComparison.new(days: 7)
        @platform_health = comparison.platform_health_summary
        @platform_scores = comparison.platform_stability_scores
      else
        @platform_health = {}
        @platform_scores = {}
      end

      # Get critical alerts (critical/high severity errors from last hour)
      # Filter by priority_level in database instead of loading all records into memory
      @critical_alerts = ErrorLog
        .where("occurred_at >= ?", 1.hour.ago)
        .where(resolved_at: nil)
        .where(priority_level: [ 3, 4 ]) # 3 = high, 4 = critical (based on severity enum)
        .order(occurred_at: :desc)
        .limit(10)
    end

    def index
      # Use Query to get filtered errors
      errors_query = Queries::ErrorsList.call(filter_params)

      # Paginate with Pagy
      @pagy, @errors = pagy(errors_query, items: params[:per_page] || 25)

      # Get dashboard stats using Query (pass application filter)
      @stats = Queries::DashboardStats.call(application_id: params[:application_id])

      # Get filter options using Query
      filter_options = Queries::FilterOptions.call
      @error_types = filter_options[:error_types]
      @platforms = filter_options[:platforms]
      @applications = filter_options[:applications]
    end

    def show
      # Eagerly load associations to avoid N+1 queries
      # - comments: Used in the comments section (@error.comments.count, @error.comments.recent_first)
      # - parent_cascade_patterns/child_cascade_patterns: Used if cascade detection is enabled
      @error = ErrorLog.includes(:comments, :parent_cascade_patterns, :child_cascade_patterns).find(params[:id])
      @related_errors = @error.related_errors(limit: 5)

      # Dispatch plugin event for error viewed
      RailsErrorDashboard::PluginRegistry.dispatch(:on_error_viewed, @error)
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

    # Phase 3: Workflow Integration Actions

    def assign
      @error = ErrorLog.find(params[:id])
      @error.assign_to!(params[:assigned_to])
      redirect_to error_path(@error)
    rescue => e
      redirect_to error_path(@error)
    end

    def unassign
      @error = ErrorLog.find(params[:id])
      @error.unassign!
      redirect_to error_path(@error)
    rescue => e
      redirect_to error_path(@error)
    end

    def update_priority
      @error = ErrorLog.find(params[:id])
      @error.update!(priority_level: params[:priority_level])
      redirect_to error_path(@error)
    rescue => e
      redirect_to error_path(@error)
    end

    def snooze
      @error = ErrorLog.find(params[:id])
      @error.snooze!(params[:hours].to_i, reason: params[:reason])
      redirect_to error_path(@error)
    rescue => e
      redirect_to error_path(@error)
    end

    def unsnooze
      @error = ErrorLog.find(params[:id])
      @error.unsnooze!
      redirect_to error_path(@error)
    rescue => e
      redirect_to error_path(@error)
    end

    def update_status
      @error = ErrorLog.find(params[:id])
      if @error.update_status!(params[:status], comment: params[:comment])
        redirect_to error_path(@error)
      else
        redirect_to error_path(@error)
      end
    rescue => e
      redirect_to error_path(@error)
    end

    def add_comment
      @error = ErrorLog.find(params[:id])
      @error.comments.create!(
        author_name: params[:author_name],
        body: params[:body]
      )
      redirect_to error_path(@error)
    rescue => e
      redirect_to error_path(@error)
    end

    def analytics
      days = (params[:days] || 30).to_i
      @days = days

      # Use Query to get analytics data (pass application filter)
      analytics = Queries::AnalyticsStats.call(days, application_id: params[:application_id])

      @error_stats = analytics[:error_stats]
      @errors_over_time = analytics[:errors_over_time]
      @errors_by_type = analytics[:errors_by_type]
      @errors_by_platform = analytics[:errors_by_platform]
      @errors_by_hour = analytics[:errors_by_hour]
      @top_users = analytics[:top_users]
      @resolution_rate = analytics[:resolution_rate]
      @mobile_errors = analytics[:mobile_errors]
      @api_errors = analytics[:api_errors]

      # Get recurring issues data
      recurring = Queries::RecurringIssues.call(days)
      @recurring_data = recurring

      # Get release correlation data
      correlation = Queries::ErrorCorrelation.new(days: days)
      @errors_by_version = correlation.errors_by_version
      @problematic_releases = correlation.problematic_releases
      @release_comparison = calculate_release_comparison

      # Get MTTR data
      mttr_data = Queries::MttrStats.call(days)
      @mttr_stats = mttr_data
      @overall_mttr = mttr_data[:overall_mttr]
      @mttr_by_platform = mttr_data[:mttr_by_platform]
    end

    def platform_comparison
      # Check if feature is enabled
      unless RailsErrorDashboard.configuration.enable_platform_comparison
        flash[:alert] = "Platform Comparison is not enabled. Enable it in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      days = (params[:days] || 7).to_i
      @days = days

      # Use Query to get platform comparison data
      comparison = Queries::PlatformComparison.new(days: days)

      @error_rate_by_platform = comparison.error_rate_by_platform
      @severity_distribution = comparison.severity_distribution_by_platform
      @resolution_times = comparison.resolution_time_by_platform
      @top_errors_by_platform = comparison.top_errors_by_platform
      @stability_scores = comparison.platform_stability_scores
      @cross_platform_errors = comparison.cross_platform_errors
      @daily_trends = comparison.daily_trend_by_platform
      @platform_health = comparison.platform_health_summary
    end

    def batch_action
      error_ids = params[:error_ids] || []
      action_type = params[:action_type]

      result = case action_type
      when "resolve"
        Commands::BatchResolveErrors.call(
          error_ids,
          resolved_by_name: params[:resolved_by_name],
          resolution_comment: params[:resolution_comment]
        )
      when "delete"
        Commands::BatchDeleteErrors.call(error_ids)
      else
        { success: false, count: 0, errors: [ "Invalid action type" ] }
      end

      if result[:success]
        flash[:notice] = "Successfully #{action_type}d #{result[:count]} error(s)"
      else
        flash[:alert] = "Batch operation failed: #{result[:errors].join(', ')}"
      end

      redirect_to errors_path
    end

    def correlation
      # Check if feature is enabled
      unless RailsErrorDashboard.configuration.enable_error_correlation
        flash[:alert] = "Error Correlation is not enabled. Enable it in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      days = (params[:days] || 30).to_i
      @days = days
      correlation = Queries::ErrorCorrelation.new(days: days)

      @errors_by_version = correlation.errors_by_version
      @errors_by_git_sha = correlation.errors_by_git_sha
      @problematic_releases = correlation.problematic_releases
      @multi_error_users = correlation.multi_error_users(min_error_types: 2)
      @time_correlated_errors = correlation.time_correlated_errors
      @period_comparison = correlation.period_comparison
      @platform_specific_errors = correlation.platform_specific_errors
    end

    def settings
      @config = RailsErrorDashboard.configuration
    end

    private

    def calculate_release_comparison
      return {} if @errors_by_version.empty? || @errors_by_version.count < 2

      versions_sorted = @errors_by_version.sort_by { |_, data| data[:last_seen] || Time.at(0) }.reverse
      latest = versions_sorted.first
      previous = versions_sorted.second

      return {} if latest.nil? || previous.nil?

      {
        latest_version: latest[0],
        latest_count: latest[1][:count],
        latest_critical: latest[1][:critical_count],
        previous_version: previous[0],
        previous_count: previous[1][:count],
        previous_critical: previous[1][:critical_count],
        change_percentage: previous[1][:count] > 0 ? ((latest[1][:count] - previous[1][:count]).to_f / previous[1][:count] * 100).round(1) : 0.0
      }
    end

    def filter_params
      params.permit(*FILTERABLE_PARAMS).to_h.symbolize_keys
    end

    def authenticate_dashboard_user!
      # Authentication is ALWAYS required - no bypass allowed in any environment
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
  end
end
