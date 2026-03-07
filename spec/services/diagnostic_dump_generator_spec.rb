# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::DiagnosticDumpGenerator do
  describe ".call" do
    subject(:dump) { described_class.call }

    it "returns a Hash" do
      expect(dump).to be_a(Hash)
    end

    it "includes :captured_at as ISO8601 string" do
      expect(dump[:captured_at]).to be_a(String)
      expect { Time.iso8601(dump[:captured_at]) }.not_to raise_error
    end

    it "includes :pid as Integer" do
      expect(dump[:pid]).to eq(Process.pid)
    end

    it "includes :uptime_seconds as a positive number" do
      expect(dump[:uptime_seconds]).to be_a(Numeric)
      expect(dump[:uptime_seconds]).to be >= 0
    end

    describe ":environment" do
      it "includes Ruby and Rails version" do
        env = dump[:environment]
        expect(env).to be_a(Hash)
        expect(env[:ruby_version]).to eq(RUBY_VERSION)
        expect(env[:rails_version]).to be_a(String)
      end

      it "includes server and database_adapter" do
        env = dump[:environment]
        expect(env).to have_key(:server)
        expect(env).to have_key(:database_adapter)
      end
    end

    describe ":system_health" do
      it "includes system health data" do
        health = dump[:system_health]
        expect(health).to be_a(Hash)
        expect(health).to have_key(:gc)
        expect(health).to have_key(:thread_count)
        expect(health).to have_key(:connection_pool)
        expect(health).to have_key(:captured_at)
      end
    end

    describe ":breadcrumbs" do
      context "when breadcrumbs are disabled" do
        before do
          allow(RailsErrorDashboard.configuration).to receive(:enable_breadcrumbs).and_return(false)
        end

        it "returns empty array" do
          expect(dump[:breadcrumbs]).to eq([])
        end
      end

      context "when breadcrumbs are enabled with data" do
        before do
          allow(RailsErrorDashboard.configuration).to receive(:enable_breadcrumbs).and_return(true)
          RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer
          RailsErrorDashboard::Services::BreadcrumbCollector.add("sql", "SELECT * FROM users")
        end

        after do
          RailsErrorDashboard::Services::BreadcrumbCollector.clear_buffer
        end

        it "returns current breadcrumbs without clearing the buffer" do
          expect(dump[:breadcrumbs]).to be_a(Array)
          expect(dump[:breadcrumbs].size).to eq(1)

          # Verify buffer was NOT cleared (non-destructive read)
          buffer = RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer
          expect(buffer.to_a.size).to eq(1)
        end
      end
    end

    describe ":threads" do
      it "returns an array of thread info hashes" do
        threads = dump[:threads]
        expect(threads).to be_a(Array)
        expect(threads.size).to be >= 1

        main_thread = threads.find { |t| t[:name] == "main" || t[:status] == "run" }
        expect(main_thread).to be_present
        expect(main_thread).to have_key(:name)
        expect(main_thread).to have_key(:status)
        expect(main_thread).to have_key(:alive)
      end
    end

    describe ":gc" do
      it "returns full GC.stat hash" do
        gc = dump[:gc]
        expect(gc).to be_a(Hash)
        expect(gc).to have_key(:heap_live_slots)
        expect(gc).to have_key(:heap_free_slots)
        expect(gc).to have_key(:major_gc_count)
        expect(gc).to have_key(:minor_gc_count)
        expect(gc).to have_key(:total_allocated_objects)
      end
    end

    describe ":object_counts" do
      it "returns ObjectSpace type counts" do
        counts = dump[:object_counts]
        expect(counts).to be_a(Hash)
        expect(counts).to have_key(:TOTAL)
        expect(counts[:TOTAL]).to be_a(Integer)
      end
    end

    context "when individual sections raise" do
      it "never raises (returns partial dump)" do
        allow(GC).to receive(:stat).and_raise(RuntimeError, "GC broken")
        allow(ObjectSpace).to receive(:count_objects).and_raise(RuntimeError, "OS broken")

        expect { dump }.not_to raise_error
        result = dump
        expect(result[:captured_at]).to be_present
        expect(result[:pid]).to eq(Process.pid)
        expect(result[:gc]).to be_nil
        expect(result[:object_counts]).to be_nil
        # Other sections should still work
        expect(result[:system_health]).to be_a(Hash)
      end
    end

    context "when everything raises catastrophically" do
      before do
        allow_any_instance_of(described_class).to receive(:process_uptime).and_raise(RuntimeError)
        allow_any_instance_of(described_class).to receive(:environment_info).and_raise(RuntimeError)
        allow_any_instance_of(described_class).to receive(:system_health).and_raise(RuntimeError)
        allow_any_instance_of(described_class).to receive(:breadcrumbs).and_raise(RuntimeError)
        allow_any_instance_of(described_class).to receive(:thread_info).and_raise(RuntimeError)
        allow_any_instance_of(described_class).to receive(:gc_info).and_raise(RuntimeError)
        allow_any_instance_of(described_class).to receive(:object_counts).and_raise(RuntimeError)
      end

      it "returns error hash instead of raising" do
        result = described_class.call
        expect(result).to be_a(Hash)
        expect(result[:captured_at]).to be_present
        expect(result[:error]).to be_a(String)
      end
    end

    it "JSON round-trips correctly" do
      json = dump.to_json
      parsed = JSON.parse(json)

      expect(parsed["captured_at"]).to be_a(String)
      expect(parsed["pid"]).to be_a(Integer)
      expect(parsed["environment"]).to be_a(Hash)
      expect(parsed["system_health"]).to be_a(Hash)
      expect(parsed["threads"]).to be_a(Array)
      expect(parsed["gc"]).to be_a(Hash)
      expect(parsed["object_counts"]).to be_a(Hash)
    end

    it "does NOT call ObjectSpace.each_object" do
      expect(ObjectSpace).not_to receive(:each_object)
      described_class.call
    end

    it "does NOT call Thread.list.map(&:backtrace)" do
      threads = Thread.list
      allow(Thread).to receive(:list).and_return(threads)
      threads.each do |t|
        expect(t).not_to receive(:backtrace)
      end
      described_class.call
    end
  end
end
