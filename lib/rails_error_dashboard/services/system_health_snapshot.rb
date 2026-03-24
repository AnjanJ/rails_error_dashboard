# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Capture runtime health metrics at error time
    #
    # Captures GC stats, process RSS memory, thread count, connection pool stats,
    # and Puma stats. NOT memoized — fresh data every call (unlike EnvironmentSnapshot).
    # Every metric call individually wrapped in rescue => nil.
    #
    # Safety contract (from HOST_APP_SAFETY.md):
    # - Total snapshot < 1ms budget
    # - NEVER ObjectSpace.each_object or ObjectSpace.count_objects (heap scan)
    # - NEVER Thread.list.map(&:backtrace) (GVL hold)
    # - Thread.list.count only (O(1), safe)
    # - Process memory: Linux procfs ONLY, no fork/subprocess ever
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
        {
          gc: gc_stats,
          process_memory_mb: process_memory_mb,
          thread_count: thread_count,
          connection_pool: connection_pool_stats,
          puma: puma_stats,
          job_queue: job_queue_stats,
          ruby_vm: ruby_vm_stats,
          yjit: yjit_stats,
          actioncable: actioncable_stats,
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

      def process_memory_mb
        # Linux ONLY — procfs read, no fork, ~0.01ms
        return nil unless File.exist?("/proc/self/status")
        content = File.read("/proc/self/status")
        match = content.match(/VmRSS:\s+(\d+)\s+kB/)
        return nil unless match
        (match[1].to_i / 1024.0).round(1)
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
      rescue => e
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
    end
  end
end
