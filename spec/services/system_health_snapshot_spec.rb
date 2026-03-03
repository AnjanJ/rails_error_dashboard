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

    it "completes within 5ms" do
      # Warm up
      described_class.capture

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      described_class.capture
      elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000

      expect(elapsed_ms).to be < 5
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

    it "does NOT call any subprocess or backtick" do
      # Verify no Kernel#` or system calls
      expect(Kernel).not_to receive(:`)
      expect(described_class).not_to receive(:`)
      expect_any_instance_of(described_class).not_to receive(:`)

      described_class.capture
    end
  end
end
