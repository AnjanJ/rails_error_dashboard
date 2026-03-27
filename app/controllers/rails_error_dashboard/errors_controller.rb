# frozen_string_literal: true

module RailsErrorDashboard
  class ErrorsController < ApplicationController
    before_action :authenticate_dashboard_user!
    before_action :set_application_context
    before_action :check_default_credentials

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
      assignee_name
      priority_level
      hide_snoozed
      hide_muted
      reopened
      sort_by
      sort_direction
    ].freeze

    def overview
      # Get dashboard stats using Query (pass application filter)
      @stats = Queries::DashboardStats.call(application_id: @current_application_id)

      # Get platform health summary (if enabled, pass application filter)
      if RailsErrorDashboard.configuration.enable_platform_comparison
        comparison = Queries::PlatformComparison.new(days: 7, application_id: @current_application_id)
        @platform_health = comparison.platform_health_summary
        @platform_scores = comparison.platform_stability_scores
      else
        @platform_health = {}
        @platform_scores = {}
      end

      # Get correlation summary (if enabled, pass application filter)
      if RailsErrorDashboard.configuration.enable_error_correlation
        correlation = Queries::ErrorCorrelation.new(days: 7, application_id: @current_application_id)
        @problematic_releases = correlation.problematic_releases.first(3)
        @time_correlated_errors = correlation.time_correlated_errors.first(3)
        @multi_error_users = correlation.multi_error_users(min_error_types: 2).first(5)
      else
        @problematic_releases = []
        @time_correlated_errors = []
        @multi_error_users = []
      end

      # Get critical alerts using Query
      @critical_alerts = Queries::CriticalAlerts.call(application_id: @current_application_id)
    end

    def index
      # Use Query to get filtered errors
      errors_query = Queries::ErrorsList.call(filter_params)

      # Paginate with Pagy
      @pagy, @errors = pagy(:offset, errors_query, limit: params[:per_page] || 25)

      # Get dashboard stats using Query (pass application filter)
      @stats = Queries::DashboardStats.call(application_id: @current_application_id)

      # Get filter options using Query (pass application filter)
      filter_options = Queries::FilterOptions.call(application_id: @current_application_id)
      @error_types = filter_options[:error_types]
      @platforms = filter_options[:platforms]
      @assignees = filter_options[:assignees]
    end

    def show
      # Eagerly load associations to avoid N+1 queries
      # - comments: Audit trail (workflow comments from snooze/mute/status changes)
      # - parent_cascade_patterns/child_cascade_patterns: Used if cascade detection is enabled
      @error = ErrorLog.includes(:comments, :parent_cascade_patterns, :child_cascade_patterns).find(params[:id])
      @related_errors = @error.related_errors(limit: 5, application_id: @current_application_id)
      @error_markdown = Services::MarkdownErrorFormatter.call(@error, related_errors: @related_errors)

      # Fetch platform issue state and comments if linked
      @platform_issue = fetch_platform_issue(@error)
      @platform_comments = fetch_platform_comments(@error)

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

    # Phase 3: Workflow Integration Actions (via Commands)

    def assign
      @error = Commands::AssignError.call(params[:id], assigned_to: params[:assigned_to])
      redirect_to error_path(@error)
    end

    def unassign
      @error = Commands::UnassignError.call(params[:id])
      redirect_to error_path(@error)
    end

    def update_priority
      @error = Commands::UpdateErrorPriority.call(params[:id], priority_level: params[:priority_level])
      redirect_to error_path(@error)
    end

    def snooze
      @error = Commands::SnoozeError.call(params[:id], hours: params[:hours].to_i, reason: params[:reason])
      redirect_to error_path(@error)
    end

    def unsnooze
      @error = Commands::UnsnoozeError.call(params[:id])
      redirect_to error_path(@error)
    end

    def mute
      @error = Commands::MuteError.call(params[:id], muted_by: params[:muted_by], reason: params[:reason])
      redirect_to error_path(@error)
    end

    def unmute
      @error = Commands::UnmuteError.call(params[:id])
      redirect_to error_path(@error)
    end

    def update_status
      result = Commands::UpdateErrorStatus.call(params[:id], status: params[:status], comment: params[:comment])
      redirect_to error_path(result[:error])
    end

    def create_issue
      dashboard_url = error_url(params[:id])
      result = Commands::CreateIssue.call(params[:id], dashboard_url: dashboard_url)

      if result[:success]
        flash[:notice] = "Issue created successfully"
        flash[:new_issue_url] = result[:issue_url]
      else
        flash[:alert] = "Failed to create issue: #{result[:error]}"
      end
      redirect_to error_path(params[:id], anchor: "issue-tracking")
    end

    def link_issue
      result = Commands::LinkExistingIssue.call(params[:id], issue_url: params[:issue_url])

      if result[:success]
        flash[:notice] = "Issue linked successfully"
      else
        flash[:alert] = "Failed to link issue: #{result[:error]}"
      end
      redirect_to error_path(params[:id], anchor: "issue-tracking")
    end

    def analytics
      days = (params[:days] || 30).to_i
      @days = days

      # Use Query to get analytics data (pass application filter)
      analytics = Queries::AnalyticsStats.call(days, application_id: @current_application_id)

      @error_stats = analytics[:error_stats]
      @errors_over_time = analytics[:errors_over_time]
      @errors_by_type = analytics[:errors_by_type]
      @errors_by_platform = analytics[:errors_by_platform]
      @errors_by_hour = analytics[:errors_by_hour]
      @top_users = analytics[:top_users]
      @resolution_rate = analytics[:resolution_rate]
      @mobile_errors = analytics[:mobile_errors]
      @api_errors = analytics[:api_errors]

      # Get recurring issues data (pass application filter)
      recurring = Queries::RecurringIssues.call(days, application_id: @current_application_id)
      @recurring_data = recurring

      # Get release correlation data (pass application filter)
      correlation = Queries::ErrorCorrelation.new(days: days, application_id: @current_application_id)
      @errors_by_version = correlation.errors_by_version
      @problematic_releases = correlation.problematic_releases
      @release_comparison = calculate_release_comparison

      # Get MTTR data (pass application filter)
      mttr_data = Queries::MttrStats.call(days, application_id: @current_application_id)
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

      # Use Query to get platform comparison data (pass application filter)
      comparison = Queries::PlatformComparison.new(days: days, application_id: @current_application_id)

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
      when "mute"
        Commands::BatchMuteErrors.call(error_ids, muted_by: params[:muted_by])
      when "unmute"
        Commands::BatchUnmuteErrors.call(error_ids)
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
      correlation = Queries::ErrorCorrelation.new(days: days, application_id: @current_application_id)

      @errors_by_version = correlation.errors_by_version
      @errors_by_git_sha = correlation.errors_by_git_sha
      @problematic_releases = correlation.problematic_releases
      @multi_error_users = correlation.multi_error_users(min_error_types: 2)
      @time_correlated_errors = correlation.time_correlated_errors
      @period_comparison = correlation.period_comparison
      @platform_specific_errors = correlation.platform_specific_errors
    end

    def releases
      days = (params[:days] || 30).to_i
      @days = days
      result = Queries::ReleaseTimeline.call(days, application_id: @current_application_id)
      all_releases = result[:releases]
      @summary = result[:summary]

      @pagy, @releases = pagy(:offset, all_releases, limit: params[:per_page] || 25)
    end

    def deprecations
      unless RailsErrorDashboard.configuration.enable_breadcrumbs
        flash[:alert] = "Breadcrumbs are not enabled. Enable them in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      days = (params[:days] || 30).to_i
      @days = days
      result = Queries::DeprecationWarnings.call(days, application_id: @current_application_id)
      all_deprecations = result[:deprecations]

      # Summary stats (computed before pagination)
      @unique_count = all_deprecations.size
      @total_count = all_deprecations.sum { |d| d[:count] }
      @affected_count = all_deprecations.flat_map { |d| d[:error_ids] }.uniq.size

      @pagy, @deprecations = pagy(:offset, all_deprecations, limit: params[:per_page] || 25)
    end

    def n_plus_one_summary
      unless RailsErrorDashboard.configuration.enable_breadcrumbs
        flash[:alert] = "Breadcrumbs are not enabled. Enable them in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      days = (params[:days] || 30).to_i
      @days = days
      result = Queries::NplusOneSummary.call(days, application_id: @current_application_id)
      all_patterns = result[:patterns]

      # Summary stats (computed before pagination)
      @unique_count = all_patterns.size
      @total_count = all_patterns.sum { |p| p[:count] }
      @affected_count = all_patterns.flat_map { |p| p[:error_ids] }.uniq.size

      @pagy, @patterns = pagy(:offset, all_patterns, limit: params[:per_page] || 25)
    end

    def cache_health_summary
      unless RailsErrorDashboard.configuration.enable_breadcrumbs
        flash[:alert] = "Breadcrumbs are not enabled. Enable them in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      days = (params[:days] || 30).to_i
      @days = days
      result = Queries::CacheHealthSummary.call(days, application_id: @current_application_id)
      all_entries = result[:entries]

      # Summary stats (computed before pagination)
      @errors_with_cache = all_entries.size
      non_nil_rates = all_entries.map { |e| e[:hit_rate] }.compact
      @avg_hit_rate = non_nil_rates.any? ? (non_nil_rates.sum / non_nil_rates.size).round(1) : nil
      @total_cache_ops = all_entries.sum { |e| e[:reads] + e[:writes] }

      @pagy, @entries = pagy(:offset, all_entries, limit: params[:per_page] || 25)
    end

    def job_health_summary
      unless RailsErrorDashboard.configuration.enable_system_health
        flash[:alert] = "System health is not enabled. Enable it in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      days = (params[:days] || 30).to_i
      @days = days
      result = Queries::JobHealthSummary.call(days, application_id: @current_application_id)
      all_entries = result[:entries]

      # Summary stats (computed before pagination)
      @errors_with_jobs = all_entries.size
      @total_failed = all_entries.sum { |e| e[:failed] || e[:errored] || 0 }
      @adapters_detected = all_entries.map { |e| e[:adapter] }.uniq

      @pagy, @entries = pagy(:offset, all_entries, limit: params[:per_page] || 25)
    end

    def database_health_summary
      unless RailsErrorDashboard.configuration.enable_system_health
        flash[:alert] = "System health is not enabled. Enable it in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      days = (params[:days] || 30).to_i
      @days = days

      # Live database health (display-time only)
      @live_health = Services::DatabaseHealthInspector.call

      # Separate host vs gem tables from live data
      all_tables = @live_health[:tables] || []
      @host_tables = all_tables.reject { |t| t[:gem_table] }
      @gem_tables = all_tables.select { |t| t[:gem_table] }

      # Historical connection pool stats
      result = Queries::DatabaseHealthSummary.call(days, application_id: @current_application_id)
      all_entries = result[:entries]

      # Summary stats (computed before pagination)
      @errors_with_pool = all_entries.size
      @max_utilization = all_entries.map { |e| e[:utilization] }.max || 0
      @total_dead = all_entries.sum { |e| e[:dead] }
      @total_waiting = all_entries.sum { |e| e[:waiting] }

      @pagy, @entries = pagy(:offset, all_entries, limit: params[:per_page] || 25)
    end

    def swallowed_exceptions
      unless RailsErrorDashboard.configuration.detect_swallowed_exceptions
        # On Ruby < 3.3, validate! auto-disables this feature — tell the user why
        if RUBY_VERSION < "3.3"
          flash[:alert] = "Swallowed exception detection requires Ruby 3.3+ (you have #{RUBY_VERSION}). Upgrade Ruby to use this feature."
        else
          flash[:alert] = "Swallowed exception detection is not enabled. Enable it in config/initializers/rails_error_dashboard.rb"
        end
        redirect_to errors_path
        return
      end

      days = (params[:days] || 30).to_i
      @days = days
      result = Queries::SwallowedExceptionSummary.call(days, application_id: @current_application_id)
      all_entries = result[:entries]

      # Summary stats (computed before pagination)
      @unique_count = all_entries.size
      @total_rescue_count = all_entries.sum { |e| e[:rescue_count] }
      @total_raise_count = all_entries.sum { |e| e[:raise_count] }

      @pagy, @entries = pagy(:offset, all_entries, limit: params[:per_page] || 25)
    end

    def rack_attack_summary
      unless RailsErrorDashboard.configuration.enable_rack_attack_tracking &&
             RailsErrorDashboard.configuration.enable_breadcrumbs
        flash[:alert] = "Rack Attack tracking is not enabled. Enable enable_rack_attack_tracking and enable_breadcrumbs in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      days = (params[:days] || 30).to_i
      @days = days
      result = Queries::RackAttackSummary.call(days, application_id: @current_application_id)
      all_events = result[:events]

      # Summary stats (computed before pagination)
      @unique_rules = all_events.size
      @total_events = all_events.sum { |e| e[:count] }
      @unique_ips = all_events.flat_map { |e| e[:ips] }.uniq.size

      @pagy, @events = pagy(:offset, all_events, limit: params[:per_page] || 25)
    end

    def actioncable_health_summary
      unless RailsErrorDashboard.configuration.enable_actioncable_tracking &&
             RailsErrorDashboard.configuration.enable_breadcrumbs
        flash[:alert] = "ActionCable tracking is not enabled. Enable enable_actioncable_tracking and enable_breadcrumbs in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      days = (params[:days] || 30).to_i
      @days = days
      result = Queries::ActionCableSummary.call(days, application_id: @current_application_id)
      all_channels = result[:channels]

      # Summary stats (computed before pagination)
      @unique_channels = all_channels.size
      @total_events = all_channels.sum { |c| c[:total_events] }
      @total_rejections = all_channels.sum { |c| c[:rejection_count] }

      @pagy, @channels = pagy(:offset, all_channels, limit: params[:per_page] || 25)
    end

    def activestorage_health_summary
      unless RailsErrorDashboard.configuration.enable_activestorage_tracking &&
             RailsErrorDashboard.configuration.enable_breadcrumbs
        flash[:alert] = "ActiveStorage tracking is not enabled. Enable enable_activestorage_tracking and enable_breadcrumbs in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      days = (params[:days] || 30).to_i
      @days = days
      result = Queries::ActiveStorageSummary.call(days, application_id: @current_application_id)
      all_services = result[:services]

      # Summary stats (computed before pagination)
      @unique_services = all_services.size
      @total_operations = all_services.sum { |s| s[:total_operations] }
      @errors_with_storage = all_services.sum { |s| s[:error_count] }

      @pagy, @services = pagy(:offset, all_services, limit: params[:per_page] || 25)
    end

    def diagnostic_dumps
      unless RailsErrorDashboard.configuration.enable_diagnostic_dump
        flash[:alert] = "Diagnostic dumps are not enabled. Enable them in config/initializers/rails_error_dashboard.rb"
        redirect_to errors_path
        return
      end

      scope = DiagnosticDump.recent
      scope = scope.where(application_id: @current_application_id) if @current_application_id.present?
      @total_dumps = scope.count

      @pagy, @dumps = pagy(:offset, scope, limit: params[:per_page] || 25)
    end

    def create_diagnostic_dump
      unless RailsErrorDashboard.configuration.enable_diagnostic_dump
        flash[:alert] = "Diagnostic dumps are not enabled."
        redirect_to errors_path
        return
      end

      dump = Services::DiagnosticDumpGenerator.call

      app_name = RailsErrorDashboard.configuration.application_name ||
                 ENV["APPLICATION_NAME"] ||
                 (defined?(Rails) && Rails.application.class.module_parent_name) ||
                 "Unknown"
      app = Commands::FindOrCreateApplication.call(app_name)

      DiagnosticDump.create!(
        application_id: app.id,
        dump_data: dump.to_json,
        captured_at: Time.current,
        note: params[:note].presence
      )

      flash[:notice] = "Diagnostic dump captured successfully."
      redirect_to diagnostic_dumps_errors_path
    rescue => e
      flash[:alert] = "Failed to capture diagnostic dump: #{e.message}"
      redirect_to diagnostic_dumps_errors_path
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

    def set_application_context
      @current_application_id = params[:application_id].presence
      @applications = Application.ordered_by_name.pluck(:name, :id)
    end

    def fetch_platform_issue(error)
      return nil unless error.external_issue_url.present? && error.external_issue_number.present?
      return nil unless RailsErrorDashboard.configuration.enable_issue_tracking

      cache_key = "red/issue_state/#{error.external_issue_provider}/#{error.external_issue_number}"
      Rails.cache.fetch(cache_key, expires_in: 60.seconds) do
        client = Services::IssueTrackerClient.from_config
        return nil unless client

        result = client.fetch_issue(number: error.external_issue_number)
        result[:success] ? result : nil
      end
    rescue => e
      nil
    end

    def fetch_platform_comments(error)
      return [] unless error.external_issue_url.present? && error.external_issue_number.present?
      return [] unless RailsErrorDashboard.configuration.enable_issue_tracking

      # Cache for 60 seconds to avoid API hammering on page refreshes
      cache_key = "red/issue_comments/#{error.external_issue_provider}/#{error.external_issue_number}"
      Rails.cache.fetch(cache_key, expires_in: 60.seconds) do
        client = Services::IssueTrackerClient.from_config
        return [] unless client

        result = client.fetch_comments(number: error.external_issue_number, per_page: 20)
        result[:success] ? result[:comments] : []
      end
    rescue => e
      []
    end

    def check_default_credentials
      @default_credentials_warning = RailsErrorDashboard.configuration.default_credentials?
    end

    def authenticate_dashboard_user!
      auth_lambda = RailsErrorDashboard.configuration.authenticate_with

      if auth_lambda
        authenticate_with_lambda(auth_lambda)
      else
        authenticate_with_basic_auth
      end
    end

    def authenticate_with_lambda(auth_lambda)
      authorized = begin
        instance_exec(&auth_lambda)
      rescue => e
        Rails.logger.error(
          "[RailsErrorDashboard] authenticate_with lambda raised #{e.class}: #{e.message}"
        )
        false
      end

      return if performed?

      unless authorized
        render plain: "Access Denied", status: :forbidden
      end
    end

    def authenticate_with_basic_auth
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
