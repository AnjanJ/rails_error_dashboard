# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Capture runtime health metrics at error time
    #
    # Captures GC stats, process memory (RSS/swap/peak), thread count, connection pool,
    # Puma stats, job queue, RubyVM/YJIT, ActionCable, file descriptors, system load,
    # system memory pressure, GC context, and TCP connection states.
    #
    # NOT memoized — fresh data every call (unlike EnvironmentSnapshot).
    # Every metric call individually wrapped in rescue => nil.
    #
    # Safety contract (from HOST_APP_SAFETY.md):
    # - Total snapshot < 1ms budget (~0.3ms typical on Linux)
    # - NEVER ObjectSpace.each_object or ObjectSpace.count_objects (heap scan)
    # - NEVER Thread.list.map(&:backtrace) (GVL hold)
    # - Thread.list.count only (O(1), safe)
    # - Process/system metrics: Linux procfs ONLY, no fork/subprocess ever
    # - All procfs reads guarded with File.exist? — returns nil on macOS/non-Linux
    # - TCP file size guard (skip if > 1MB) to protect against connection leak scenarios
    # - No new gems, no global state, no Thread.current, no mutex
    class SystemHealthSnapshot
      # Capture current system health metrics
      # @return [Hash] Health snapshot (always safe, never raises)
      def self.capture
        new.capture
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] SystemHealthSnapshot.capture failed: #{e.message}")
        { captured_at: Time.current.iso8601 }
      end

      # @return [Hash] Health snapshot
      def capture
        mem = process_memory
        {
          gc: gc_stats,
          gc_latest: gc_latest,
          process_memory: mem,
          process_memory_mb: mem&.dig(:rss_mb),  # backward compat
          thread_count: thread_count,
          connection_pool: connection_pool_stats,
          puma: puma_stats,
          job_queue: job_queue_stats,
          ruby_vm: ruby_vm_stats,
          yjit: yjit_stats,
          actioncable: actioncable_stats,
          file_descriptors: file_descriptors,
          system_load: system_load,
          system_memory: system_memory,
          tcp_connections: tcp_connections,
          captured_at: Time.current.iso8601
        }
      end

      private

      def gc_stats
        stats = GC.stat
        {
          heap_live_slots: stats[:heap_live_slots],
          heap_free_slots: stats[:heap_free_slots],
          major_gc_count: stats[:major_gc_count],
          total_allocated_objects: stats[:total_allocated_objects]
        }
      rescue => e
        nil
      end

      # GC.latest_gc_info — context about the most recent GC run
      # Works on all platforms (Ruby API, no procfs)
      def gc_latest
        info = GC.latest_gc_info
        {
          major_by: info[:major_by]&.to_s,
          gc_by: info[:gc_by]&.to_s,
          state: info[:state]&.to_s,
          immediate_sweep: info[:immediate_sweep]
        }
      rescue => e
        nil
      end

      # Process memory from /proc/self/status — single file read, 4 fields extracted
      # Linux ONLY — returns nil on macOS/non-Linux (~0.02ms)
      def process_memory
        return nil unless File.exist?("/proc/self/status")
        status = File.read("/proc/self/status")
        rss = status[/^VmRSS:\s+(\d+)/, 1]&.to_i
        return nil unless rss
        {
          rss_mb: (rss / 1024.0).round(1),
          swap_mb: (status[/^VmSwap:\s+(\d+)/, 1].to_i / 1024.0).round(1),
          rss_peak_mb: (status[/^VmHWM:\s+(\d+)/, 1].to_i / 1024.0).round(1),
          os_threads: status[/^Threads:\s+(\d+)/, 1]&.to_i
        }
      rescue => e
        nil
      end

      def thread_count
        Thread.list.count  # O(1), safe — NEVER .map(&:backtrace)
      rescue => e
        nil
      end

      def connection_pool_stats
        pool = ActiveRecord::Base.connection_pool
        stat = pool.stat
        { size: stat[:size], busy: stat[:busy], dead: stat[:dead],
          idle: stat[:idle], waiting: stat[:waiting] }
      rescue => e
        nil  # Pool may be closed during shutdown
      end

      def puma_stats
        return nil unless defined?(Puma) && Puma.respond_to?(:stats)
        raw = JSON.parse(Puma.stats)
        { pool_capacity: raw["pool_capacity"], max_threads: raw["max_threads"],
          running: raw["running"], backlog: raw["backlog"] }
      rescue => e
        nil
      end

      # Auto-detect and capture job queue stats
      # @return [Hash, nil] Job queue stats with :adapter key, or nil
      def job_queue_stats
        if defined?(::Sidekiq::Stats)
          sidekiq_stats
        elsif defined?(::SolidQueue)
          solid_queue_stats
        elsif defined?(::GoodJob)
          good_job_stats
        end
      rescue => e
        nil
      end

      def sidekiq_stats
        stats = ::Sidekiq::Stats.new
        {
          adapter: "sidekiq",
          enqueued: stats.enqueued,
          processed: stats.processed,
          failed: stats.failed,
          dead: stats.dead_size,
          scheduled: stats.scheduled_size,
          retry: stats.retry_size,
          workers: stats.workers_size
        }
      rescue => e
        nil
      end

      def solid_queue_stats
        {
          adapter: "solid_queue",
          ready: (::SolidQueue::ReadyExecution.count rescue nil),
          scheduled: (::SolidQueue::ScheduledExecution.count rescue nil),
          claimed: (::SolidQueue::ClaimedExecution.count rescue nil),
          failed: (::SolidQueue::FailedExecution.count rescue nil),
          blocked: (::SolidQueue::BlockedExecution.count rescue nil)
        }
      rescue => e
        nil
      end

      def good_job_stats
        {
          adapter: "good_job",
          queued: (::GoodJob::Job.where(finished_at: nil, error: nil).count rescue nil),
          errored: (::GoodJob::Job.where.not(error: nil).where(finished_at: nil).count rescue nil),
          finished: (::GoodJob::Job.where.not(finished_at: nil).count rescue nil)
        }
      rescue => e
        nil
      end

      # RubyVM.stat — constant/method cache invalidation rates
      # Keys vary by Ruby version; pass through full hash for forward-compat
      # Ruby 3.2+: constant_cache_invalidations, constant_cache_misses,
      #            global_cvar_state, next_shape_id, shape_cache_size
      def ruby_vm_stats
        return nil unless defined?(RubyVM) && RubyVM.respond_to?(:stat)
        RubyVM.stat
      rescue => e
        nil
      end

      # ActionCable connection stats — read-only, <0.1ms
      def actioncable_stats
        return nil unless defined?(ActionCable) && defined?(ActionCable::Server)
        server = ActionCable.server
        {
          connections: server.connections.count,
          adapter: server.pubsub&.class&.name&.demodulize
        }
      rescue LoadError, StandardError => e
        nil
      end

      # RubyVM::YJIT.runtime_stats — JIT compilation health
      # Cherry-picks diagnostic keys (full hash has 30+ entries)
      def yjit_stats
        return nil unless defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?) && RubyVM::YJIT.enabled?
        raw = RubyVM::YJIT.runtime_stats
        {
          inline_code_size: raw[:inline_code_size],
          code_region_size: raw[:code_region_size],
          compiled_iseq_count: raw[:compiled_iseq_count],
          compiled_block_count: raw[:compiled_block_count],
          compile_time_ns: raw[:compile_time_ns],
          invalidation_count: raw[:invalidation_count],
          invalidate_method_lookup: raw[:invalidate_method_lookup],
          invalidate_constant_state_bump: raw[:invalidate_constant_state_bump],
          object_shape_count: raw[:object_shape_count]
        }
      rescue => e
        nil
      end

      # File descriptor count vs ulimit — detects FD exhaustion
      # Linux ONLY — /proc/self/fd (~0.05ms)
      def file_descriptors
        return nil unless File.exist?("/proc/self/fd")
        open_count = Dir.children("/proc/self/fd").size
        soft_limit, _hard = Process.getrlimit(:NOFILE)
        {
          open: open_count,
          limit: soft_limit,
          utilization_pct: soft_limit > 0 ? (open_count.to_f / soft_limit * 100).round(1) : nil
        }
      rescue => e
        nil
      end

      # System load averages from /proc/loadavg + CPU count
      # Linux ONLY — returns nil on macOS (~0.01ms)
      def system_load
        return nil unless File.exist?("/proc/loadavg")
        parts = File.read("/proc/loadavg").split
        require "etc" unless defined?(Etc)
        cpu_count = Etc.nprocessors rescue nil
        load_1m = parts[0].to_f
        {
          load_1m: load_1m,
          load_5m: parts[1].to_f,
          load_15m: parts[2].to_f,
          cpu_count: cpu_count,
          load_ratio: cpu_count && cpu_count > 0 ? (load_1m / cpu_count).round(2) : nil
        }
      rescue => e
        nil
      end

      # System-wide memory pressure from /proc/meminfo
      # Linux ONLY — returns nil on macOS (~0.02ms)
      def system_memory
        return nil unless File.exist?("/proc/meminfo")
        meminfo = File.read("/proc/meminfo")
        total = meminfo[/^MemTotal:\s+(\d+)/, 1]&.to_i
        available = meminfo[/^MemAvailable:\s+(\d+)/, 1]&.to_i
        swap_total = meminfo[/^SwapTotal:\s+(\d+)/, 1]&.to_i
        swap_free = meminfo[/^SwapFree:\s+(\d+)/, 1]&.to_i
        {
          total_mb: total ? (total / 1024.0).round(0) : nil,
          available_mb: available ? (available / 1024.0).round(0) : nil,
          used_pct: total && available && total > 0 ? ((1 - available.to_f / total) * 100).round(1) : nil,
          swap_used_mb: swap_total && swap_free ? ((swap_total - swap_free) / 1024.0).round(0) : nil
        }
      rescue => e
        nil
      end

      # TCP connection states from /proc/self/net/tcp (+tcp6)
      # Linux ONLY — returns nil on macOS (~0.05ms typical)
      # Safety: skips if file > 1MB (protects against connection leak scenarios)
      def tcp_connections
        path = "/proc/self/net/tcp"
        return nil unless File.exist?(path)
        return nil if File.size(path) > 1_048_576
        lines = File.readlines(path).drop(1)
        states = lines.map { |l| l.strip.split[3] }
        result = {
          established: states.count("01"),
          close_wait: states.count("08"),
          time_wait: states.count("06"),
          listen: states.count("0A")
        }
        path6 = "/proc/self/net/tcp6"
        if File.exist?(path6) && File.size(path6) <= 1_048_576
          lines6 = File.readlines(path6).drop(1)
          states6 = lines6.map { |l| l.strip.split[3] }
          result[:established] += states6.count("01")
          result[:close_wait] += states6.count("08")
          result[:time_wait] += states6.count("06")
          result[:listen] += states6.count("0A")
        end
        result
      rescue => e
        nil
      end
    end
  end
end
