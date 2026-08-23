# frozen_string_literal: true

module RailsErrorDashboard
  class ErrorsController < ApplicationController
    before_action :authenticate_dashboard_user!
    before_action :set_application_context
    before_action :check_default_credentials
    before_action :load_storm_banner

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
      user_id
      app_version
      git_sha
      sort_by
      sort_direction
    ].freeze

    # Batch action param => the key naming its outcome. English happens to form
    # all four by adding "d"/"ed"; most languages do not, so each outcome is
    # named rather than derived from the param.
    BATCH_OUTCOMES = {
      "resolve" => "resolved",
      "mute" => "muted",
      "unmute" => "unmuted",
      "delete" => "deleted"
    }.freeze

    # Named once: the check and the message that reports it were both writing
    # 4000, and the copy that drifts is the one the user reads.
    AI_HELP_QUESTION_LIMIT = 4000

    # The initializer every "not enabled" notice points at. A path, not prose.
    INITIALIZER_PATH = "config/initializers/rails_error_dashboard.rb"

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

      # Paginate with Pagy. raise_range_error makes pagy 43.x raise Pagy::RangeError
      # on out-of-range pages (e.g. ?page=999999) so application_controller.rb's
      # rescue_from can redirect to a valid page. Without this, pagy 43.x silently
      # returns an empty result and users see "All clear!" instead of their data.
      @pagy, @errors = pagy(:offset, errors_query, limit: params[:per_page] || 25, raise_range_error: true)

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

      redirect_to error_path(@error, **app_context_params)
    end

    # Phase 3: Workflow Integration Actions (via Commands)

    def assign
      @error = Commands::AssignError.call(params[:id], assigned_to: params[:assigned_to])
      redirect_to error_path(@error, **app_context_params)
    end

    def unassign
      @error = Commands::UnassignError.call(params[:id])
      redirect_to error_path(@error, **app_context_params)
    end

    def update_priority
      @error = Commands::UpdateErrorPriority.call(params[:id], priority_level: params[:priority_level])
      redirect_to error_path(@error, **app_context_params)
    end

    def snooze
      @error = Commands::SnoozeError.call(params[:id], hours: params[:hours].to_i, reason: params[:reason])
      redirect_to error_path(@error, **app_context_params)
    end

    def unsnooze
      @error = Commands::UnsnoozeError.call(params[:id])
      redirect_to error_path(@error, **app_context_params)
    end

    def mute
      @error = Commands::MuteError.call(params[:id], muted_by: params[:muted_by], reason: params[:reason])
      redirect_to error_path(@error, **app_context_params)
    end

    def unmute
      @error = Commands::UnmuteError.call(params[:id])
      redirect_to error_path(@error, **app_context_params)
    end

    def update_status
      result = Commands::UpdateErrorStatus.call(params[:id], status: params[:status], comment: params[:comment])
      redirect_to error_path(result[:error], **app_context_params)
    end

    def create_issue
      dashboard_url = error_url(params[:id])
      result = Commands::CreateIssue.call(params[:id], dashboard_url: dashboard_url)

      if result[:success]
        flash[:notice] = red_t("red.flash.issue.created")
        flash[:new_issue_url] = result[:issue_url]
      else
        flash[:alert] = red_t("red.flash.issue.create_failed", reason: result[:error])
      end
      redirect_to error_path(params[:id], anchor: "issue-tracking", **app_context_params)
    end

    def link_issue
      result = Commands::LinkExistingIssue.call(params[:id], issue_url: params[:issue_url])

      if result[:success]
        flash[:notice] = red_t("red.flash.issue.linked")
      else
        flash[:alert] = red_t("red.flash.issue.link_failed", reason: result[:error])
      end
      redirect_to error_path(params[:id], anchor: "issue-tracking", **app_context_params)
    end

    def ai_help
      unless RailsErrorDashboard.configuration.llm_configured?
        render json: { error: red_t("red.flash.ai_help.not_configured") }, status: :not_found
        return
      end

      question = params[:question].to_s.strip
      if question.blank?
        render json: { error: red_t("red.flash.ai_help.blank_question") }, status: :unprocessable_entity
        return
      end

      if question.length > AI_HELP_QUESTION_LIMIT
        render json: {
          error: red_t("red.flash.ai_help.question_too_long",
                       limit: helpers.number_with_delimiter(AI_HELP_QUESTION_LIMIT))
        }, status: :unprocessable_entity
        return
      end

      error = ErrorLog.includes(:comments, :parent_cascade_patterns, :child_cascade_patterns).find(params[:id])
      related_errors = error.related_errors(limit: 5, application_id: @current_application_id)
      context = Services::MarkdownErrorFormatter.call(error, related_errors: related_errors)

      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["X-Accel-Buffering"] = "no"

      self.response_body = Enumerator.new do |stream|
        begin
          result = Services::LlmClient.stream(error: error, question: question, context: context) do |text|
            stream << sse_event("chunk", text: text)
          end
          stream << sse_event("done", result)
        rescue Services::LlmClient::ConfigurationError, Services::LlmClient::RequestError => e
          stream << sse_event("error", error: e.message)
        end
      end
    end

    def analytics
      days = days_param(default: 30)
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
        flash[:alert] = feature_disabled_message("platform_comparison")
        redirect_to errors_path(**app_context_params)
        return
      end

      days = days_param(default: 7)
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
        Commands::BatchMuteErrors.call(error_ids, muted_by: params[:muted_by], reason: params[:reason])
      when "unmute"
        Commands::BatchUnmuteErrors.call(error_ids)
      when "delete"
        Commands::BatchDeleteErrors.call(error_ids)
      else
        { success: false, count: 0, errors: [ red_t("red.commands.invalid_action") ] }
      end

      if result[:success]
        # One key per outcome rather than "Successfully #{action_type}d": the
        # original conjugated English past tense by appending a "d" to the raw
        # param, which no other language can be asked to do.
        #
        # An unrecognized action cannot reach here (the case above returns
        # success: false), but the lookup still degrades rather than raising —
        # a flash message is never worth a 500 on the error dashboard.
        outcome = BATCH_OUTCOMES[action_type]
        flash[:notice] = if outcome
          red_tp("red.flash.batch.#{outcome}", count: result[:count])
        else
          red_t("red.commands.invalid_action")
        end
      else
        flash[:alert] = red_t("red.flash.batch.failed", reason: result[:errors].join(", "))
      end

      redirect_to errors_path(**app_context_params)
    end

    def correlation
      # Check if feature is enabled
      unless RailsErrorDashboard.configuration.enable_error_correlation
        flash[:alert] = feature_disabled_message("error_correlation")
        redirect_to errors_path(**app_context_params)
        return
      end

      days = days_param(default: 30)
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
      days = days_param(default: 30)
      @days = days
      result = Queries::ReleaseTimeline.call(days, application_id: @current_application_id)
      all_releases = result[:releases]
      @summary = result[:summary]

      @pagy, @releases = pagy(:offset, all_releases, limit: params[:per_page] || 25)
    end

    def storms
      result = Queries::StormHistory.call
      @active_storm = result[:active]
      @storm_events = result[:events]
    end

    def user_impact
      days = days_param(default: 30)
      @days = days
      result = Queries::UserImpactSummary.call(days, application_id: @current_application_id)
      all_entries = result[:entries]
      @summary = result[:summary]

      @pagy, @entries = pagy(:offset, all_entries, limit: params[:per_page] || 25)
    end

    def deprecations
      unless RailsErrorDashboard.configuration.enable_breadcrumbs
        flash[:alert] = feature_disabled_message("breadcrumbs", plural: true)
        redirect_to errors_path(**app_context_params)
        return
      end

      days = days_param(default: 30)
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
        flash[:alert] = feature_disabled_message("breadcrumbs", plural: true)
        redirect_to errors_path(**app_context_params)
        return
      end

      days = days_param(default: 30)
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
        flash[:alert] = feature_disabled_message("breadcrumbs", plural: true)
        redirect_to errors_path(**app_context_params)
        return
      end

      days = days_param(default: 30)
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
        flash[:alert] = feature_disabled_message("system_health")
        redirect_to errors_path(**app_context_params)
        return
      end

      days = days_param(default: 30)
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
        flash[:alert] = feature_disabled_message("system_health")
        redirect_to errors_path(**app_context_params)
        return
      end

      days = days_param(default: 30)
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
          flash[:alert] = red_t("red.flash.swallowed_requires_ruby", version: RUBY_VERSION)
        else
          flash[:alert] = feature_disabled_message("swallowed_exceptions")
        end
        redirect_to errors_path(**app_context_params)
        return
      end

      days = days_param(default: 30)
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
      unless RailsErrorDashboard.configuration.enable_rack_attack_tracking
        flash[:alert] = feature_disabled_message("rack_attack", options: "enable_rack_attack_tracking = true", set: true)
        redirect_to errors_path(**app_context_params)
        return
      end

      # Distinguishes "gem not installed" from "installed but no rules matched"
      # in the empty state — both otherwise render an identical blank page.
      @rack_attack_missing = !defined?(::Rack::Attack)

      days = days_param(default: 30)
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
        flash[:alert] = feature_disabled_message("actioncable", options: "enable_actioncable_tracking and enable_breadcrumbs")
        redirect_to errors_path(**app_context_params)
        return
      end

      days = days_param(default: 30)
      @days = days
      result = Queries::ActionCableSummary.call(days, application_id: @current_application_id)
      all_channels = result[:channels]

      # Summary stats (computed before pagination)
      @unique_channels = all_channels.size
      @total_events = all_channels.sum { |c| c[:total_events] }
      @total_rejections = all_channels.sum { |c| c[:rejection_count] }

      @pagy, @channels = pagy(:offset, all_channels, limit: params[:per_page] || 25)
    end

    def llm_health_summary
      unless RailsErrorDashboard.configuration.enable_llm_observability &&
             RailsErrorDashboard.configuration.enable_breadcrumbs
        @feature_disabled = true
        @days = days_param(default: 30)
        @models = []
        @totals = Queries::LlmHealthSummary.blank_totals
        @pagy = nil
        return
      end

      days = days_param(default: 30)
      @days = days
      result = Queries::LlmHealthSummary.call(days, application_id: @current_application_id)
      @totals = result[:totals]
      all_models = result[:models]

      @pagy, @models = pagy(:offset, all_models, limit: params[:per_page] || 25)
    end

    def activestorage_health_summary
      unless RailsErrorDashboard.configuration.enable_activestorage_tracking &&
             RailsErrorDashboard.configuration.enable_breadcrumbs
        flash[:alert] = feature_disabled_message("activestorage", options: "enable_activestorage_tracking and enable_breadcrumbs")
        redirect_to errors_path(**app_context_params)
        return
      end

      days = days_param(default: 30)
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
        flash[:alert] = feature_disabled_message("diagnostic_dumps", plural: true)
        redirect_to errors_path(**app_context_params)
        return
      end

      scope = DiagnosticDump.recent
      scope = scope.where(application_id: @current_application_id) if @current_application_id.present?
      @total_dumps = scope.count

      @pagy, @dumps = pagy(:offset, scope, limit: params[:per_page] || 25)
    end

    def create_diagnostic_dump
      unless RailsErrorDashboard.configuration.enable_diagnostic_dump
        flash[:alert] = red_t("red.flash.diagnostic_dump.disabled")
        redirect_to errors_path(**app_context_params)
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

      flash[:notice] = red_t("red.flash.diagnostic_dump.captured")
      redirect_to diagnostic_dumps_errors_path
    rescue => e
      flash[:alert] = red_t("red.flash.diagnostic_dump.failed", message: e.message)
      redirect_to diagnostic_dumps_errors_path
    end

    def enable_coverage
      unless RailsErrorDashboard.configuration.enable_coverage_tracking
        flash[:alert] = red_t("red.flash.coverage.not_enabled")
        redirect_to errors_path(**app_context_params)
        return
      end

      if Services::CoverageTracker.enable!
        flash[:notice] = red_t("red.flash.coverage.enabled")
      else
        flash[:alert] = red_t("red.flash.coverage.unavailable")
      end
      redirect_back fallback_location: errors_path
    end

    def disable_coverage
      Services::CoverageTracker.disable!
      flash[:notice] = red_t("red.flash.coverage.disabled")
      redirect_back fallback_location: errors_path
    end

    def test_error
      exception = RailsErrorDashboard::TestError.new(
        "[RED Test] This is a test error sent from the dashboard to verify " \
        "that error capture and notification delivery are working correctly. " \
        "It is safe to resolve or delete this error."
      )
      exception.set_backtrace(caller)

      Commands::LogError.call(exception, { request: request, source: "dashboard.test_error" })

      flash[:notice] = red_t("red.flash.test_error.logged")
      redirect_to errors_path(**app_context_params)
    rescue => e
      flash[:alert] = red_t("red.flash.test_error.failed", message: e.message)
      redirect_to settings_path(**app_context_params)
    end

    def settings
      @config = RailsErrorDashboard.configuration
    end

    private

    # "X is not enabled. Enable it in <initializer>" was written out eleven
    # times with only the feature name changing. One helper, so the wording
    # cannot drift page to page — and the initializer path is interpolated
    # rather than translated, because it is a path.
    #
    # English agrees the verb and pronoun with the feature name, so a plural
    # feature ("Breadcrumbs are... Enable them") needs a different key from a
    # singular one ("System health is... Enable it"). The caller says which;
    # inferring it from the English string would be guessing at grammar.
    #
    # @param feature [String] a key under red.flash.features
    # @param plural [Boolean] whether the feature name takes a plural verb
    # @param options [String, nil] config option names to cite instead
    # @param set [Boolean] use "Set" rather than "Enable" for those options
    def feature_disabled_message(feature, plural: false, options: nil, set: false)
      name = red_t("red.flash.features.#{feature}")

      if options
        key = set ? "red.flash.not_enabled_set_options" : "red.flash.not_enabled_options"
        red_t(key, feature: name, options: options, file: INITIALIZER_PATH)
      else
        key = plural ? "red.flash.not_enabled_plural" : "red.flash.not_enabled"
        red_t(key, feature: name, file: INITIALIZER_PATH)
      end
    end

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

    def sse_event(event, payload)
      "event: #{event}\ndata: #{payload.to_json}\n\n"
    end

    def filter_params
      params.permit(*FILTERABLE_PARAMS).to_h.symbolize_keys
    end

    # Coerce params[:days] into a sane integer in [1, 365]. Without clamping,
    # a request like ?days=99999999 would scan the full table on every health
    # query, defeating index pruning and burning CPU.
    def days_param(default:)
      raw = params[:days].presence || default
      raw.to_i.clamp(1, 365)
    end

    def set_application_context
      @current_application_id = params[:application_id].presence
      @applications = Application.ordered_by_name.pluck(:name, :id)
    end

    # Preserves the application_id param across redirects
    def app_context_params
      @current_application_id.present? ? { application_id: @current_application_id } : {}
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

    def load_storm_banner
      @storm_banner_loaded = true
      @storm_banner_event = Queries::StormHistory.banner_event
    end
  end
end
