# RED code audit (v0.11.0) — what actually ships. 247 spec files. Ruby >=3.2, Rails >=7.0. Runtime deps: pagy, groupdate, concurrent-ruby (3, not 2). chartkick/turbo-rails/browser/rack-attack/opentelemetry/faraday optional.

## Implemented (with mechanism/constraints)
1. Local vars: services/local_variable_capturer.rb, TracePoint(:raise), enable_local_variables=false, max_count 15/depth 3/str 200. Ruby 3.2+.
2. Instance vars on tp.self: same capturer, enable_instance_variables=false, max 20.
3. Swallowed exceptions: services/swallowed_exception_tracker.rb, TracePoint(:raise)+TracePoint(:rescue), thread-local LRU, flush job → own table; aggregate page. detect_swallowed_exceptions=false. **Ruby 3.3+ hard gate (auto-disables <3.3).**
4. Crash capture: services/crash_capture.rb, at_exit { capture!($!) } → JSON file → import! at next boot as ErrorLog. Skips SystemExit.success?/SignalException. enable_crash_capture=false. Not Signal.trap.
5. Diagnostic dump: services/diagnostic_dump_generator.rb; POST from dashboard or rake; SystemHealthSnapshot + Thread.list (names/status, no backtraces) + GC.stat + ObjectSpace.count_objects + breadcrumbs + uptime → diagnostic_dumps table. enable_diagnostic_dump=false.
6. Production coverage: services/coverage_tracker.rb, Coverage.setup(oneshot_lines: true)+resume, peek_result per file, toggled from dashboard; piggybacks SimpleCov. enable_coverage_tracking=false. Ruby 3.2+.
7. System health snapshot at error time: services/system_health_snapshot.rb. Fields: gc, gc_latest, process_memory (VmRSS/VmSwap/VmHWM/Threads via /proc), thread_count, connection_pool (AR pool.stat), puma (Puma.stats), job_queue (Sidekiq/SolidQueue/GoodJob auto), ruby_vm (RubyVM.stat), yjit, actioncable, file_descriptors, system_load, system_memory, tcp_connections. enable_system_health=false. **procfs fields Linux-only.**
8. Job Health / DB Health / Cache Health pages: aggregate system_health JSON stored ON ERROR ROWS (not live) — empty without enable_system_health. DB page also has live DatabaseHealthInspector (pg_stat_user_tables/indexes/activity) — **PostgreSQL-only**. Cache page = display-time analysis of cache_read/write breadcrumbs (needs breadcrumbs).
9. ActionCable monitoring: subscribers/action_cable_subscriber.rb via AS::Notifications (perform_action, transmit, subscription confirm/reject) → breadcrumbs + snapshot; enable_actioncable_tracking=false, requires breadcrumbs.
10. Rack::Attack: subscribers/rack_attack_subscriber.rb on throttle/blocklist/track.rack_attack; thread-local LRU → own table; at_exit flush; per-discriminator; AI-agent UA classifier (services/ai_agent_classifier.rb). Does NOT need breadcrumbs. enable_rack_attack_tracking=false.
11. Breadcrumbs: AS::Notifications on sql.active_record, process_action, cache_read/write, perform.active_job, deliver.action_mailer, deprecation.rails; ring buffer 40; enable_breadcrumbs=false. N+1: display-time SQL fingerprint normalisation, threshold 3, aggregate page, enable_n_plus_one_detection=true (when breadcrumbs on). Deprecations aggregate page — **only works if host sets deprecation behavior :notify; gem never sets it; docs don't say (production default = empty page).**
12. LLM observability: three paths — (a) Faraday middleware host inserts manually (detects api.openai.com/api.anthropic.com; tokens + tool calls); (b) LlmSpanProcessor on OTel tracer_provider reading GenAI semconv (covers ruby_llm via opentelemetry-instrumentation-ruby_llm); (c) manual AS::Notifications.instrument("red.llm_call"/"red.llm_tool_call"). Cost table hardcoded (Claude 4.x, GPT-4o/o1, Gemini 2.5). **Nothing auto-instruments any SDK.** content capture default false. Per-model health page. enable_llm_observability=false (needs breadcrumbs).
13. AI Help: services/llm_client.rb Net::HTTP streaming to OpenAI (Responses/Chat) or Anthropic Messages; SSE to page; BYO key (RED_LLM_API_KEY, string or lambda); context = MarkdownErrorFormatter + 5 related errors. Off by default.
14. Copy as curl (services/curl_generator.rb), Copy as RSpec (rspec_generator.rb), Copy for LLM (markdown_error_formatter.rb) — server-rendered, client copy.
15. OTel: outbound export of gem's own pipeline as rails_error_dashboard.* spans (capture/breadcrumbs/health/notifications), enable_otel_export=false, needs opentelemetry-api. **Inbound = GenAI spans only (LLM), no general span ingestion, no OTLP receiver.**
16. Storm protection: services/storm_protection/{gate,circuit_breaker,count_buffer,fingerprint_buckets}; states closed/shedding/open/half_open; Concurrent::AtomicFixnum; count-only mode buffers + flush job every 30s; storm_events table + storms page + banner; Gate.issue_creation_allowed? consumed by IssueTrackerSubscriber; notifications_suppressed?. **enable_storm_protection=true by default.** Per-process. **Overhead benchmark (2.4µs) is documented-only: no script, no timing spec, only a "Benchmarked." comment.**
17. Issue trackers: GitHub, GitLab, Codeberg, Linear clients; manual create, link existing, auto-create by severity ([:critical,:high]), lifecycle jobs (close/reopen linked, recurrence comment), inbound webhooks controller with signature verification for all four; dashboard mirrors issue state. enable_issue_tracking=false.
18. Notifications: Slack, Email, Discord, PagerDuty, Webhooks. **No Telegram, no Teams.** Throttler = severity floor + cooldown 5min + milestones [10,50,100,500,1000]; mute short-circuit; environment allowlist checked in 3 places.
19. Analytics: baseline (mean+stddev, outlier removal, throttled alerts, enable_baseline_alerts=false), spike detection (always on), Pearson correlation, cascade detector, occurrence pattern detector, platform comparison, user impact, priority score (always on), similar errors (Jaccard+Levenshtein), co-occurring. Most behind enable_* false.
20. Workflow: resolve/assign/unassign/snooze/unsnooze/mute/unmute/status/priority/comment; batch resolve/delete/mute/unmute; auto-reopen (find_or_increment_error reopen_existing, just_reopened); custom_fingerprint lambda. **No merge/split UI; ADVANCED_ERROR_GROUPING.md is about similarity/cascades, not grouping knobs.**
21. Source code: source_code_reader (Rails.root at display time, path validation), git_blame_reader (Open3 git blame), link generator for GitHub/GitLab/Bitbucket/Codeberg/Gitea/Forgejo. Off by default. Source must be on dashboard host.
22. i18n: 11 locales; PrivateBackend < I18n::Backend::Simple, never touches host I18n; locale into jobs; bin/i18n-check, bin/i18n-merge; session-persisted picker. dashboard_locale="en".
23. Environment awareness: column + [environment, occurred_at] index; match dimension not fingerprint input; backfill rake; notification_environments allowlist.
24. Data: PG/MySQL/Trilogy/SQLite branches; separate DB via ErrorLogsRecord connects_to (guarded); BRIN + DATE_TRUNC functional indexes (PG-only); retention job (host must schedule; retention_days=90); sampling_rate (rand); ignored_exceptions; max_backtrace_lines=100; sensitive_data_filter (filter_sensitive_data=true); async_logging=false, async_adapter :sidekiq|:solid_queue|:async (**GoodJob not an async adapter option**).
25. Auth: HTTP Basic (secure_compare) or authenticate_with lambda (instance_exec); default creds gandalf/youshallnotpass with allowlist + banner; API-only mode inserts Flash/Cookies/Session middleware; CSP nonces on inline script/style; dashboard rate limiter middleware (enable_rate_limiting=false). **Layout loads Bootstrap, Bootstrap Icons, Chart.js, chartjs-adapter-date-fns, Chartkick, highlight.js from cdn.jsdelivr.net + Google Fonts — air-gapped hosts get unstyled, chartless dashboard.** Gem's own CSS/JS inline.
26. Multi-app: Application model, auto-name from Rails.application module_parent_name, application_id FK, per-app filter, rake list/backfill/app_stats.
27. Plugins: plugin.rb hooks (on_register, on_error_logged/recurred/resolved, batch_resolved/deleted, on_error_viewed), PluginRegistry.dispatch safe_execute, sample plugins (audit_log, jira SAMPLE, metrics); notification_callbacks. **No dedicated plugin spec.**
28. Mobile: **documented-only guide** — host writes its own controller calling RailsErrorDashboard::ManualErrorReporter.report; gem ships NO ingest endpoint; platform_detector tags iOS/Android/Expo from UA (optional browser gem).
29. Real-time: Turbo::StreamsChannel broadcast_prepend_to, only if host has turbo-rails + ActionCable pubsub; **no polling fallback**. Keyboard shortcuts (?, /, r, a, [, ]). Dark/light theme localStorage.
30. Confirmed absent: health-check endpoint, JSON API, MCP server (0 hits).

## Discrepancies (do not claim)
1. 2.4µs/2.95µs/0.2µs overhead numbers: unreproducible (README only).
2. README L697 says "Seven shipped locales" vs 11 elsewhere.
3. Deprecation tracking requires host `:notify` behavior; undocumented; production default yields empty page.
4. "Zero asset pipeline / fully self-contained" true only for gem's own CSS/JS; third-party JS/CSS/fonts from CDN.
5. Job/DB Health pages are not live monitors (error-row aggregation); DB inspector PG-only, gate undocumented in FEATURES.md.
6. Mobile integration = host-written code; README "React Native, Flutter" over-implies.
7. Real-time has no fallback; gemspec "falls back to page refresh" = manual.
8. "OpenTelemetry in + out" — inbound is GenAI-only.
9. LLM observability not auto-instrumented for any SDK.
10. "24+ features" is marketing; ~35 enable_* switches.
11. "2 required deps" — actually 3 + rails.
12. No plugin spec.
13. Telegram/Teams not implemented.
14. No grouping controls beyond custom_fingerprint.

## Surprises (shipped, undersold)
- ActiveStorage service health page (enable_activestorage_tracking, needs breadcrumbs).
- AI-agent traffic classifier for Rack::Attack track (GPTBot/ClaudeBot etc.) — not in README.
- Release tracking page (release_timeline, comparison; reads HEROKU_SLUG_COMMIT/RENDER_GIT_COMMIT).
- Scheduled digests (daily/weekly mailer + rake).
- Boot-time environment snapshot (Ruby/Rails/gem versions, web server) stored per error.
- Settings page showing effective config; Test error button.
- Analytics cache manager; MTTR stats, critical alerts, recurring issues, co-occurring queries.
- Cause-chain extractor; severity classifier with custom_severity_rules.
- Generators install/solid_queue/uninstall; rake toolbox (verify, cleanup_resolved, diagnostic_dump, retention_cleanup, send_digest, drop, backfill_environments).
- FEATURES.md tier list omits OTel export, Storm Protection, Environment Awareness, Release Tracking, Digests, Coverage, AI Help, Copy as curl/RSpec.
