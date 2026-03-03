# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::BreadcrumbCollector do
  before do
    described_class.clear_buffer
    RailsErrorDashboard.configuration.enable_breadcrumbs = true
    RailsErrorDashboard.configuration.breadcrumb_buffer_size = 40
    RailsErrorDashboard.configuration.breadcrumb_categories = nil
  end

  after do
    described_class.clear_buffer
    RailsErrorDashboard.reset_configuration!
  end

  describe "RingBuffer" do
    let(:buffer) { described_class::RingBuffer.new(3) }

    it "stores entries up to max size" do
      buffer.add({ m: "a" })
      buffer.add({ m: "b" })
      buffer.add({ m: "c" })

      expect(buffer.to_a.size).to eq(3)
    end

    it "wraps around when exceeding max size" do
      buffer.add({ m: "a" })
      buffer.add({ m: "b" })
      buffer.add({ m: "c" })
      buffer.add({ m: "d" })

      result = buffer.to_a
      expect(result.size).to eq(3)
      expect(result.map { |e| e[:m] }).to eq(%w[ b c d ])
    end

    it "returns entries in insertion order" do
      buffer.add({ m: "first" })
      buffer.add({ m: "second" })

      result = buffer.to_a
      expect(result.map { |e| e[:m] }).to eq(%w[ first second ])
    end

    it "handles single element" do
      buffer.add({ m: "only" })
      expect(buffer.to_a).to eq([ { m: "only" } ])
    end

    it "returns empty array when no entries" do
      expect(buffer.to_a).to eq([])
    end
  end

  describe ".init_buffer" do
    it "creates a RingBuffer on Thread.current" do
      described_class.init_buffer
      expect(Thread.current[:red_breadcrumbs]).to be_a(described_class::RingBuffer)
    end

    it "uses configured buffer size" do
      RailsErrorDashboard.configuration.breadcrumb_buffer_size = 10
      described_class.init_buffer
      buffer = Thread.current[:red_breadcrumbs]

      # Fill beyond size to verify wrapping
      15.times { |i| buffer.add({ m: i.to_s }) }
      expect(buffer.to_a.size).to eq(10)
    end
  end

  describe ".clear_buffer" do
    it "sets Thread.current[:red_breadcrumbs] to nil" do
      described_class.init_buffer
      expect(Thread.current[:red_breadcrumbs]).not_to be_nil

      described_class.clear_buffer
      expect(Thread.current[:red_breadcrumbs]).to be_nil
    end
  end

  describe ".add" do
    before { described_class.init_buffer }

    it "appends a breadcrumb with correct format" do
      described_class.add("sql", "SELECT * FROM users")

      result = described_class.harvest
      expect(result.size).to eq(1)

      crumb = result.first
      expect(crumb[:c]).to eq("sql")
      expect(crumb[:m]).to eq("SELECT * FROM users")
      expect(crumb[:t]).to be_a(Integer)
      expect(crumb[:d]).to be_nil
    end

    it "includes duration_ms when provided" do
      described_class.add("sql", "SELECT 1", duration_ms: 1.5)

      crumb = described_class.harvest.first
      expect(crumb[:d]).to eq(1.5)
    end

    it "includes metadata when provided" do
      described_class.add("custom", "checkout", metadata: { cart_id: 123 })

      crumb = described_class.harvest.first
      expect(crumb[:meta]).to eq({ cart_id: "123" })
    end

    it "does not include metadata key when nil" do
      described_class.add("sql", "SELECT 1")

      crumb = described_class.harvest.first
      expect(crumb).not_to have_key(:meta)
    end

    it "truncates long messages to 500 chars" do
      long_message = "x" * 600
      described_class.add("sql", long_message)

      crumb = described_class.harvest.first
      expect(crumb[:m].length).to eq(500)
    end

    it "truncates metadata values to 200 chars" do
      described_class.add("custom", "test", metadata: { key: "v" * 300 })

      crumb = described_class.harvest.first
      expect(crumb[:meta][:key].length).to eq(200)
    end

    it "limits metadata to 10 keys" do
      meta = (1..15).map { |i| [ "key#{i}".to_sym, "value#{i}" ] }.to_h
      described_class.add("custom", "test", metadata: meta)

      crumb = described_class.harvest.first
      expect(crumb[:meta].size).to eq(10)
    end

    it "filters categories based on breadcrumb_categories config" do
      RailsErrorDashboard.configuration.breadcrumb_categories = [ :sql, :controller ]

      described_class.add("sql", "SELECT 1")
      described_class.add("cache", "cache read: key")
      described_class.add("controller", "UsersController#index")

      result = described_class.harvest
      expect(result.size).to eq(2)
      expect(result.map { |c| c[:c] }).to eq(%w[ sql controller ])
    end

    it "no-ops when buffer is nil (no request context)" do
      described_class.clear_buffer
      expect { described_class.add("sql", "SELECT 1") }.not_to raise_error
    end

    it "never raises even with bad input" do
      # nil message
      expect { described_class.add("sql", nil) }.not_to raise_error
      # non-string category
      expect { described_class.add(123, "test") }.not_to raise_error
      # non-hash metadata
      expect { described_class.add("sql", "test", metadata: "bad") }.not_to raise_error
    end

    it "respects buffer size (wraps around)" do
      RailsErrorDashboard.configuration.breadcrumb_buffer_size = 3
      described_class.clear_buffer
      described_class.init_buffer

      5.times { |i| described_class.add("sql", "query #{i}") }

      result = described_class.harvest
      expect(result.size).to eq(3)
      expect(result.map { |c| c[:m] }).to eq([ "query 2", "query 3", "query 4" ])
    end
  end

  describe ".harvest" do
    before { described_class.init_buffer }

    it "returns array of breadcrumb hashes" do
      described_class.add("sql", "SELECT 1")
      described_class.add("controller", "UsersController#index")

      result = described_class.harvest
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
    end

    it "clears the buffer after harvest" do
      described_class.add("sql", "SELECT 1")
      described_class.harvest

      expect(described_class.harvest).to eq([])
    end

    it "returns empty array when buffer is nil" do
      described_class.clear_buffer
      expect(described_class.harvest).to eq([])
    end

    it "returns empty array when buffer is empty" do
      expect(described_class.harvest).to eq([])
    end
  end

  describe ".current_buffer" do
    it "returns the buffer when initialized" do
      described_class.init_buffer
      expect(described_class.current_buffer).to be_a(described_class::RingBuffer)
    end

    it "returns nil when not initialized" do
      described_class.clear_buffer
      expect(described_class.current_buffer).to be_nil
    end
  end

  describe ".filter_sensitive" do
    before do
      RailsErrorDashboard.configuration.filter_sensitive_data = true
      RailsErrorDashboard::Services::SensitiveDataFilter.reset!
      allow(Rails.application.config).to receive(:filter_parameters).and_return([])
    end

    after do
      RailsErrorDashboard::Services::SensitiveDataFilter.reset!
    end

    it "redacts SQL with sensitive patterns" do
      breadcrumbs = [
        { c: "sql", m: "SELECT * FROM users WHERE password='secret123'", t: 1000 }
      ]

      result = described_class.filter_sensitive(breadcrumbs)
      expect(result.first[:m]).to include("[FILTERED]")
      expect(result.first[:m]).not_to include("secret123")
    end

    it "redacts custom breadcrumb messages with sensitive data" do
      breadcrumbs = [
        { c: "custom", m: "login attempt password=hunter2", t: 1000 }
      ]

      result = described_class.filter_sensitive(breadcrumbs)
      expect(result.first[:m]).to include("[FILTERED]")
      expect(result.first[:m]).not_to include("hunter2")
    end

    it "redacts metadata values with sensitive keys" do
      breadcrumbs = [
        { c: "custom", m: "checkout", t: 1000, meta: { "password" => "secret", "cart_id" => "123" } }
      ]

      result = described_class.filter_sensitive(breadcrumbs)
      expect(result.first[:meta]["password"]).to eq("[FILTERED]")
      expect(result.first[:meta]["cart_id"]).to eq("123")
    end

    it "returns breadcrumbs unchanged when filtering disabled" do
      RailsErrorDashboard.configuration.filter_sensitive_data = false

      breadcrumbs = [
        { c: "sql", m: "SELECT password FROM users", t: 1000 }
      ]

      result = described_class.filter_sensitive(breadcrumbs)
      expect(result.first[:m]).to eq("SELECT password FROM users")
    end

    it "returns empty array for empty input" do
      expect(described_class.filter_sensitive([])).to eq([])
    end

    it "never raises" do
      expect { described_class.filter_sensitive(nil) }.not_to raise_error
      expect { described_class.filter_sensitive("bad") }.not_to raise_error
    end
  end
end
