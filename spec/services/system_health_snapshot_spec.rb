# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::SystemHealthSnapshot do
  describe ".capture" do
    subject(:snapshot) { described_class.capture }

    it "returns a Hash" do
      expect(snapshot).to be_a(Hash)
    end

    it "includes :captured_at as ISO8601 string" do
      expect(snapshot[:captured_at]).to be_a(String)
      expect { Time.iso8601(snapshot[:captured_at]) }.not_to raise_error
    end

    describe ":gc sub-hash" do
      it "includes GC stats" do
        gc = snapshot[:gc]
        expect(gc).to be_a(Hash)
        expect(gc[:heap_live_slots]).to be_a(Integer)
        expect(gc[:heap_free_slots]).to be_a(Integer)
        expect(gc[:major_gc_count]).to be_a(Integer)
        expect(gc[:total_allocated_objects]).to be_a(Integer)
      end
    end

    describe ":process_memory_mb" do
      if File.exist?("/proc/self/status")
        it "returns a Float > 0 on Linux" do
          expect(snapshot[:process_memory_mb]).to be_a(Float)
          expect(snapshot[:process_memory_mb]).to be > 0
        end
      else
        it "returns nil on non-Linux" do
          expect(snapshot[:process_memory_mb]).to be_nil
        end
      end
    end

    describe ":thread_count" do
      it "returns an Integer >= 1" do
        expect(snapshot[:thread_count]).to be_a(Integer)
        expect(snapshot[:thread_count]).to be >= 1
      end
    end

    describe ":connection_pool" do
      it "includes pool stats" do
        pool = snapshot[:connection_pool]
        expect(pool).to be_a(Hash)
        expect(pool).to have_key(:size)
        expect(pool).to have_key(:busy)
        expect(pool).to have_key(:dead)
        expect(pool).to have_key(:idle)
        expect(pool).to have_key(:waiting)
      end
    end

    describe ":puma" do
      it "returns nil when Puma is not running as server" do
        # In test environment, Puma.stats is not available
        expect(snapshot[:puma]).to be_nil
      end
    end

    it "is NOT memoized (different object_id across calls)" do
      snapshot1 = described_class.capture
      snapshot2 = described_class.capture
      expect(snapshot1.object_id).not_to eq(snapshot2.object_id)
    end

    it "JSON round-trips preserve structure" do
      json = snapshot.to_json
      parsed = JSON.parse(json, symbolize_names: true)

      expect(parsed[:gc]).to be_a(Hash)
      expect(parsed[:thread_count]).to be_a(Integer)
      expect(parsed[:captured_at]).to be_a(String)
    end

    it "JSON round-trips preserve ruby_vm and yjit keys" do
      # Stub YJIT so we have data to round-trip
      yjit_mod = Module.new do
        def self.enabled? = true

        def self.runtime_stats
          { inline_code_size: 1024, code_region_size: 2048, compiled_iseq_count: 100,
            compiled_block_count: 200, compile_time_ns: 5_000_000, invalidation_count: 3,
            invalidate_method_lookup: 1, invalidate_constant_state_bump: 2, object_shape_count: 50 }
        end
      end
      stub_const("RubyVM::YJIT", yjit_mod)

      result = described_class.capture
      json = result.to_json
      parsed = JSON.parse(json, symbolize_names: true)

      expect(parsed[:ruby_vm]).to be_a(Hash)
      expect(parsed[:ruby_vm][:constant_cache_invalidations]).to be_a(Integer)
      expect(parsed[:ruby_vm][:constant_cache_misses]).to be_a(Integer)

      expect(parsed[:yjit]).to be_a(Hash)
      expect(parsed[:yjit][:compiled_iseq_count]).to eq(100)
      expect(parsed[:yjit][:invalidation_count]).to eq(3)
      expect(parsed[:yjit][:code_region_size]).to eq(2048)
    end

    it "completes within 10ms" do
      # Warm up
      described_class.capture

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      described_class.capture
      elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000

      expect(elapsed_ms).to be < 10
    end

    context "when GC.stat raises" do
      before do
        allow(GC).to receive(:stat).and_raise(RuntimeError, "GC broken")
      end

      it "does not raise" do
        expect { snapshot }.not_to raise_error
      end

      it "returns nil for :gc" do
        expect(snapshot[:gc]).to be_nil
      end

      it "still includes other metrics" do
        expect(snapshot[:thread_count]).to be_a(Integer)
        expect(snapshot[:captured_at]).to be_present
      end
    end

    context "when ALL methods fail" do
      before do
        allow(GC).to receive(:stat).and_raise(RuntimeError)
        allow(Thread).to receive(:list).and_raise(RuntimeError)
        allow(ActiveRecord::Base).to receive(:connection_pool).and_raise(RuntimeError)
      end

      it "returns a hash with :captured_at" do
        result = described_class.capture
        expect(result).to be_a(Hash)
        expect(result[:captured_at]).to be_present
      end
    end

    describe ":job_queue" do
      it "returns nil when no adapter is defined" do
        expect(snapshot[:job_queue]).to be_nil
      end

      context "when Sidekiq is available" do
        before do
          sidekiq_stats_class = Class.new do
            def enqueued = 5
            def processed = 100
            def failed = 2
            def dead_size = 1
            def scheduled_size = 3
            def retry_size = 0
            def workers_size = 4
          end

          stub_const("Sidekiq::Stats", sidekiq_stats_class)
        end

        it "captures Sidekiq stats" do
          result = described_class.capture
          jq = result[:job_queue]
          expect(jq).to be_a(Hash)
          expect(jq[:adapter]).to eq("sidekiq")
          expect(jq[:enqueued]).to eq(5)
          expect(jq[:dead]).to eq(1)
          expect(jq[:workers]).to eq(4)
        end
      end

      context "when SolidQueue is available" do
        before do
          stub_const("SolidQueue", Module.new)
          stub_const("SolidQueue::ReadyExecution", double(count: 3))
          stub_const("SolidQueue::ScheduledExecution", double(count: 1))
          stub_const("SolidQueue::ClaimedExecution", double(count: 2))
          stub_const("SolidQueue::FailedExecution", double(count: 0))
          stub_const("SolidQueue::BlockedExecution", double(count: 0))
        end

        it "captures SolidQueue stats" do
          result = described_class.capture
          jq = result[:job_queue]
          expect(jq).to be_a(Hash)
          expect(jq[:adapter]).to eq("solid_queue")
          expect(jq[:ready]).to eq(3)
          expect(jq[:claimed]).to eq(2)
          expect(jq[:failed]).to eq(0)
        end
      end

      context "when adapter raises" do
        before do
          sidekiq_stats_class = Class.new do
            def initialize
              raise RuntimeError, "Redis down"
            end
          end
          stub_const("Sidekiq::Stats", sidekiq_stats_class)
        end

        it "returns nil" do
          result = described_class.capture
          expect(result[:job_queue]).to be_nil
        end
      end
    end

    describe ":ruby_vm" do
      it "returns a Hash with RubyVM.stat keys" do
        vm = snapshot[:ruby_vm]
        expect(vm).to be_a(Hash)
        expect(vm).to have_key(:constant_cache_invalidations)
        expect(vm).to have_key(:constant_cache_misses)
        expect(vm[:constant_cache_invalidations]).to be_a(Integer)
        expect(vm[:constant_cache_misses]).to be_a(Integer)
      end

      context "when RubyVM.stat raises" do
        before do
          allow(RubyVM).to receive(:stat).and_raise(RuntimeError, "VM broken")
        end

        it "returns nil" do
          expect(snapshot[:ruby_vm]).to be_nil
        end

        it "still includes other metrics" do
          expect(snapshot[:thread_count]).to be_a(Integer)
          expect(snapshot[:captured_at]).to be_present
        end
      end
    end

    describe ":yjit" do
      it "returns nil when YJIT is not enabled" do
        # YJIT is typically not enabled in test (no --yjit flag)
        # If it IS enabled, this test still passes (returns hash or nil)
        unless defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?) && RubyVM::YJIT.enabled?
          expect(snapshot[:yjit]).to be_nil
        end
      end

      context "when YJIT is enabled" do
        before do
          yjit_mod = Module.new do
            def self.enabled? = true

            def self.runtime_stats
              {
                inline_code_size: 1024,
                code_region_size: 2048,
                compiled_iseq_count: 100,
                compiled_block_count: 200,
                compile_time_ns: 5_000_000,
                invalidation_count: 3,
                invalidate_method_lookup: 1,
                invalidate_constant_state_bump: 2,
                object_shape_count: 50
              }
            end
          end

          stub_const("RubyVM::YJIT", yjit_mod)
        end

        it "returns cherry-picked YJIT stats" do
          result = described_class.capture
          yj = result[:yjit]
          expect(yj).to be_a(Hash)
          expect(yj[:compiled_iseq_count]).to eq(100)
          expect(yj[:compiled_block_count]).to eq(200)
          expect(yj[:invalidation_count]).to eq(3)
          expect(yj[:code_region_size]).to eq(2048)
          expect(yj[:compile_time_ns]).to eq(5_000_000)
          expect(yj[:object_shape_count]).to eq(50)
        end
      end

      context "when YJIT runtime_stats raises" do
        before do
          yjit_mod = Module.new do
            def self.enabled? = true
            def self.runtime_stats = raise(RuntimeError, "YJIT broken")
          end

          stub_const("RubyVM::YJIT", yjit_mod)
        end

        it "returns nil" do
          result = described_class.capture
          expect(result[:yjit]).to be_nil
        end
      end

      context "when YJIT runtime_stats returns partial keys" do
        before do
          yjit_mod = Module.new do
            def self.enabled? = true

            def self.runtime_stats
              # Future Ruby version with only some keys
              { compiled_iseq_count: 42, invalidation_count: 7 }
            end
          end

          stub_const("RubyVM::YJIT", yjit_mod)
        end

        it "returns nil for missing keys without error" do
          result = described_class.capture
          yj = result[:yjit]
          expect(yj).to be_a(Hash)
          expect(yj[:compiled_iseq_count]).to eq(42)
          expect(yj[:invalidation_count]).to eq(7)
          expect(yj[:code_region_size]).to be_nil
          expect(yj[:compile_time_ns]).to be_nil
          expect(yj[:compiled_block_count]).to be_nil
          expect(yj[:object_shape_count]).to be_nil
        end
      end
    end

    describe ":gc_latest" do
      it "returns a Hash with GC context" do
        gcl = snapshot[:gc_latest]
        expect(gcl).to be_a(Hash)
        expect(gcl).to have_key(:gc_by)
        expect(gcl).to have_key(:state)
        expect(gcl).to have_key(:major_by)
        expect(gcl).to have_key(:immediate_sweep)
      end

      it "gc_by is a String" do
        expect(snapshot[:gc_latest][:gc_by]).to be_a(String)
      end

      it "state is a String" do
        expect(snapshot[:gc_latest][:state]).to be_a(String)
      end
    end

    describe ":process_memory" do
      if File.exist?("/proc/self/status")
        it "returns a Hash with rss_mb, swap_mb, rss_peak_mb, os_threads on Linux" do
          pm = snapshot[:process_memory]
          expect(pm).to be_a(Hash)
          expect(pm[:rss_mb]).to be_a(Float)
          expect(pm[:rss_mb]).to be > 0
          expect(pm[:swap_mb]).to be_a(Float)
          expect(pm[:swap_mb]).to be >= 0
          expect(pm[:rss_peak_mb]).to be_a(Float)
          expect(pm[:rss_peak_mb]).to be >= pm[:rss_mb]
          expect(pm[:os_threads]).to be_a(Integer)
          expect(pm[:os_threads]).to be >= 1
        end

        it "preserves process_memory_mb backward compat" do
          expect(snapshot[:process_memory_mb]).to eq(snapshot[:process_memory][:rss_mb])
        end
      else
        it "returns nil on non-Linux" do
          expect(snapshot[:process_memory]).to be_nil
        end

        it "process_memory_mb is also nil on non-Linux" do
          expect(snapshot[:process_memory_mb]).to be_nil
        end
      end
    end

    describe ":file_descriptors" do
      if File.exist?("/proc/self/fd")
        it "returns a Hash with open, limit, utilization_pct on Linux" do
          fd = snapshot[:file_descriptors]
          expect(fd).to be_a(Hash)
          expect(fd[:open]).to be_a(Integer)
          expect(fd[:open]).to be > 0
          expect(fd[:limit]).to be_a(Integer)
          expect(fd[:limit]).to be > 0
          expect(fd[:utilization_pct]).to be_a(Float)
          expect(fd[:utilization_pct]).to be >= 0
          expect(fd[:utilization_pct]).to be <= 100
        end
      else
        it "returns nil on non-Linux" do
          expect(snapshot[:file_descriptors]).to be_nil
        end
      end
    end

    describe ":system_load" do
      if File.exist?("/proc/loadavg")
        it "returns a Hash with load averages and cpu_count on Linux" do
          sl = snapshot[:system_load]
          expect(sl).to be_a(Hash)
          expect(sl[:load_1m]).to be_a(Float)
          expect(sl[:load_5m]).to be_a(Float)
          expect(sl[:load_15m]).to be_a(Float)
          expect(sl[:cpu_count]).to be_a(Integer)
          expect(sl[:cpu_count]).to be >= 1
          expect(sl[:load_ratio]).to be_a(Float)
        end
      else
        it "returns nil on non-Linux" do
          expect(snapshot[:system_load]).to be_nil
        end
      end
    end

    describe ":system_memory" do
      if File.exist?("/proc/meminfo")
        it "returns a Hash with total, available, used_pct, swap on Linux" do
          sm = snapshot[:system_memory]
          expect(sm).to be_a(Hash)
          expect(sm[:total_mb]).to be_a(Numeric)
          expect(sm[:total_mb]).to be > 0
          expect(sm[:available_mb]).to be_a(Numeric)
          expect(sm[:used_pct]).to be_a(Float)
          expect(sm[:used_pct]).to be >= 0
          expect(sm[:used_pct]).to be <= 100
          expect(sm[:swap_used_mb]).to be_a(Numeric)
        end
      else
        it "returns nil on non-Linux" do
          expect(snapshot[:system_memory]).to be_nil
        end
      end
    end

    describe ":tcp_connections" do
      if File.exist?("/proc/self/net/tcp")
        it "returns a Hash with connection state counts on Linux" do
          tcp = snapshot[:tcp_connections]
          expect(tcp).to be_a(Hash)
          expect(tcp[:established]).to be_a(Integer)
          expect(tcp[:established]).to be >= 0
          expect(tcp[:close_wait]).to be_a(Integer)
          expect(tcp[:time_wait]).to be_a(Integer)
          expect(tcp[:listen]).to be_a(Integer)
        end
      else
        it "returns nil on non-Linux" do
          expect(snapshot[:tcp_connections]).to be_nil
        end
      end
    end

    describe ":actioncable" do
      it "returns nil when ActionCable is not defined" do
        # ActionCable may or may not be defined in test env
        # If not defined, should return nil
        if defined?(ActionCable)
          # If it IS defined, stub server to test behavior
          server = double("ActionCable::Server", connections: [], pubsub: nil)
          allow(ActionCable).to receive(:server).and_return(server)
          ac = snapshot[:actioncable]
          expect(ac).to be_a(Hash)
          expect(ac[:connections]).to eq(0)
        else
          expect(snapshot[:actioncable]).to be_nil
        end
      end

      it "captures connection count and adapter when ActionCable is available" do
        pubsub = double("ActionCable::SubscriptionAdapter::Async")
        allow(pubsub).to receive(:class).and_return(ActionCable::SubscriptionAdapter::Async) if defined?(ActionCable::SubscriptionAdapter::Async)
        allow(pubsub).to receive_message_chain(:class, :name).and_return("ActionCable::SubscriptionAdapter::Async")

        server = double("ActionCable::Server", connections: [ 1, 2, 3 ], pubsub: pubsub)
        stub_const("ActionCable", Module.new) unless defined?(ActionCable)
        stub_const("ActionCable::Server", Class.new) unless defined?(ActionCable::Server)
        allow(ActionCable).to receive(:server).and_return(server)

        result = described_class.capture
        ac = result[:actioncable]
        expect(ac).to be_a(Hash)
        expect(ac[:connections]).to eq(3)
        expect(ac[:adapter]).to eq("Async")
      end

      it "returns nil when server raises" do
        stub_const("ActionCable", Module.new) unless defined?(ActionCable)
        stub_const("ActionCable::Server", Class.new) unless defined?(ActionCable::Server)
        allow(ActionCable).to receive(:server).and_raise(RuntimeError, "not configured")

        result = described_class.capture
        expect(result[:actioncable]).to be_nil
      end
    end

    it "does NOT call any subprocess or backtick" do
      # Verify no Kernel#` or system calls
      expect(Kernel).not_to receive(:`)
      expect(described_class).not_to receive(:`)
      expect_any_instance_of(described_class).not_to receive(:`)

      described_class.capture
    end
  end
end
