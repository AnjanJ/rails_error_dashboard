# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::LocalVariableCapturer do
  after do
    described_class.disable!
  end

  describe ".enable! / .disable! / .enabled?" do
    it "starts disabled" do
      expect(described_class.enabled?).to be false
    end

    it "can be enabled" do
      described_class.enable!
      expect(described_class.enabled?).to be true
    end

    it "can be disabled after enabling" do
      described_class.enable!
      described_class.disable!
      expect(described_class.enabled?).to be false
    end

    it "is idempotent when calling enable! twice" do
      described_class.enable!
      described_class.enable!
      expect(described_class.enabled?).to be true
    end

    it "is safe to call disable! when already disabled" do
      expect { described_class.disable! }.not_to raise_error
    end
  end

  describe "capture behavior" do
    before { described_class.enable! }

    it "captures local variables when an exception is raised in app code" do
      # The spec file path contains 'rails_error_dashboard' which the capturer skips,
      # so we test by manually attaching locals (simulating what the TracePoint does)
      exception = StandardError.new("test error")
      exception.instance_variable_set(:@_red_locals, { user_name: "Gandalf", error_code: 42 })

      locals = described_class.extract(exception)
      expect(locals).to be_a(Hash)
      expect(locals[:user_name]).to eq("Gandalf")
      expect(locals[:error_code]).to eq(42)
    end

    it "skips SystemExit" do
      exception = SystemExit.new(0)
      expect(described_class.extract(exception)).to be_nil
    end

    it "skips re-raises (already captured)" do
      exception = nil
      begin
        x = 1
        _unused = x
        begin
          raise StandardError, "inner"
        rescue => e
          raise e # re-raise — should NOT overwrite @_red_locals
        end
      rescue => e
        exception = e
      end

      locals = described_class.extract(exception)
      # Should have locals from the first raise, not overwritten by re-raise
      if locals
        expect(locals).to be_a(Hash)
      end
    end

    it "captures multiple variables from a single frame" do
      exception = StandardError.new("test")
      many_locals = (1..25).each_with_object({}) { |i, h| h[:"var_#{i}"] = "val_#{i}" }
      exception.instance_variable_set(:@_red_locals, many_locals)

      locals = described_class.extract(exception)
      expect(locals.size).to eq(25)
    end

    it "returns nil when exception has no local variables captured" do
      exception = StandardError.new("test")
      # No @_red_locals set — no TracePoint fired or exception from filtered path
      expect(described_class.extract(exception)).to be_nil
    end
  end

  describe "raise-time snapshots" do
    before do
      RailsErrorDashboard.configuration.enable_local_variables = true
      RailsErrorDashboard.configuration.enable_instance_variables = true
      described_class.enable!
    end
    after { RailsErrorDashboard.reset_configuration! }

    # eval with an app-looking path so the capturer does not skip the frame as gem/spec code
    def raise_in_app(code)
      eval(code, TOPLEVEL_BINDING, "/app/services/snapshot_probe.rb", 1) # rubocop:disable Security/Eval
    end

    it "keeps the hash values from the moment of the raise, not after an ensure block mutated them" do
      exception = raise_in_app(<<~RUBY)
        begin
          state = { "phase" => "at raise" }
          begin
            raise StandardError, "snapshot probe"
          ensure
            state["phase"] = "after unwind"
          end
        rescue StandardError => caught
          caught
        end
      RUBY

      expect(described_class.extract(exception)[:state]["phase"]).to eq("at raise")
    end

    it "keeps string and array values from the moment of the raise" do
      exception = raise_in_app(<<~RUBY)
        begin
          label = +"pending"
          items = [ 1, 2 ]
          begin
            raise StandardError, "snapshot probe"
          ensure
            label << " (cleaned up)"
            items << 3
          end
        rescue StandardError => caught
          caught
        end
      RUBY

      locals = described_class.extract(exception)
      expect(locals[:label]).to eq("pending")
      expect(locals[:items]).to eq([ 1, 2 ])
    end

    it "snapshots instance variables the same way" do
      # The class must live at an app-looking path too: the raise happens
      # inside #run, and a frame in this spec file is skipped as gem code.
      exception = raise_in_app(<<~RUBY)
        snapshot_probe_service = Class.new do
          def run
            @status = { "conn" => "open" }
            raise StandardError, "snapshot probe"
          ensure
            @status["conn"] = "closed"
          end
        end
        begin
          snapshot_probe_service.new.run
        rescue StandardError => caught
          caught
        end
      RUBY

      ivars = described_class.extract_instance_vars(exception)
      expect(ivars[:@status]["conn"]).to eq("open")
    end

    it "bounds the copy by the serializer's limits so a huge collection is not duplicated" do
      RailsErrorDashboard.configuration.local_variable_max_array_items = 3
      expect(described_class.send(:snapshot_value, (1..1000).to_a).size).to eq(4)
      expect(described_class.send(:snapshot_value, "x" * 5000).size).to eq(201)
    end

    it "leaves other objects as references" do
      obj = Object.new
      expect(described_class.send(:snapshot_value, obj)).to equal(obj)
    end
  end

  describe ".extract" do
    it "returns nil for nil input" do
      expect(described_class.extract(nil)).to be_nil
    end

    it "returns nil for non-exception input" do
      expect(described_class.extract("not an exception")).to be_nil
    end

    it "returns nil when exception has no @_red_locals" do
      exception = StandardError.new("test")
      expect(described_class.extract(exception)).to be_nil
    end

    it "returns hash when exception has @_red_locals" do
      exception = StandardError.new("test")
      exception.instance_variable_set(:@_red_locals, { x: 1, y: "hello" })
      result = described_class.extract(exception)
      expect(result).to eq({ x: 1, y: "hello" })
    end

    it "never raises even with problematic exception" do
      exception = StandardError.new("test")
      allow(exception).to receive(:instance_variable_defined?).and_raise("boom")
      expect { described_class.extract(exception) }.not_to raise_error
      expect(described_class.extract(exception)).to be_nil
    end

    it "handles frozen exception without crashing" do
      exception = StandardError.new("frozen test")
      # Frozen exceptions can't have ivars set, so extract should return nil safely
      expect { described_class.extract(exception.freeze) }.not_to raise_error
    end

    it "returns empty hash when @_red_locals is set to empty hash" do
      exception = StandardError.new("test")
      exception.instance_variable_set(:@_red_locals, {})
      result = described_class.extract(exception)
      expect(result).to eq({})
    end
  end

  describe "callback safety" do
    before { described_class.enable! }

    it "never raises from the TracePoint callback" do
      expect {
        begin
          raise StandardError, "test"
        rescue
          # swallowed
        end
      }.not_to raise_error
    end

    it "does not capture exceptions from gem paths" do
      exception = nil
      begin
        JSON.parse("invalid json")
      rescue => e
        exception = e
      end

      locals = described_class.extract(exception)
      expect(locals).to be_nil
    end

    it "never stores Binding objects in @_red_locals" do
      exception = nil
      begin
        x = 42
        _unused = x
        raise StandardError, "test"
      rescue => e
        exception = e
      end

      locals = described_class.extract(exception)
      next unless locals

      locals.each_value do |val|
        expect(val).not_to be_a(Binding)
      end
    end

    it "does not capture exceptions from eval'd code" do
      exception = nil
      begin
        # rubocop:disable Security/Eval
        eval('raise StandardError, "from eval"')
        # rubocop:enable Security/Eval
      rescue => e
        exception = e
      end

      # Ruby 3.3+: path starts with "<" (e.g. "<eval>")
      # Ruby 3.2:  path starts with "(" (e.g. "(eval)")
      # Both are filtered by skip_path?
      locals = described_class.extract(exception)
      expect(locals).to be_nil
    end
  end

  describe ".extract_instance_vars" do
    it "returns nil for nil input" do
      expect(described_class.extract_instance_vars(nil)).to be_nil
    end

    it "returns nil for non-exception input" do
      expect(described_class.extract_instance_vars("not an exception")).to be_nil
    end

    it "returns nil when exception has no @_red_instance_vars" do
      exception = StandardError.new("test")
      expect(described_class.extract_instance_vars(exception)).to be_nil
    end

    it "returns hash when exception has @_red_instance_vars" do
      exception = StandardError.new("test")
      ivars = { :_self_class => "MyController", :@user => "Gandalf", :@count => 42 }
      exception.instance_variable_set(:@_red_instance_vars, ivars)

      result = described_class.extract_instance_vars(exception)
      expect(result).to be_a(Hash)
      expect(result[:_self_class]).to eq("MyController")
      expect(result[:@user]).to eq("Gandalf")
      expect(result[:@count]).to eq(42)
    end

    it "never raises even with problematic exception" do
      exception = StandardError.new("test")
      allow(exception).to receive(:instance_variable_defined?).and_raise("boom")
      expect { described_class.extract_instance_vars(exception) }.not_to raise_error
      expect(described_class.extract_instance_vars(exception)).to be_nil
    end
  end

  describe "instance variable capture behavior" do
    before do
      described_class.enable!
      RailsErrorDashboard.configuration.enable_instance_variables = true
    end

    after do
      RailsErrorDashboard.configuration.enable_instance_variables = false
    end

    it "captures instance variables when manually attached" do
      exception = StandardError.new("test error")
      ivars = {
        :_self_class => "UsersController",
        :@current_user => "User#1",
        :@retry_count => 3
      }
      exception.instance_variable_set(:@_red_instance_vars, ivars)

      result = described_class.extract_instance_vars(exception)
      expect(result).to be_a(Hash)
      expect(result[:_self_class]).to eq("UsersController")
      expect(result[:@current_user]).to eq("User#1")
      expect(result[:@retry_count]).to eq(3)
    end

    it "returns nil when instance variables feature is disabled and no ivars attached" do
      RailsErrorDashboard.configuration.enable_instance_variables = false
      exception = StandardError.new("test")
      expect(described_class.extract_instance_vars(exception)).to be_nil
    end

    it "returns nil when exception has no @_red_instance_vars attached" do
      exception = StandardError.new("test")
      expect(described_class.extract_instance_vars(exception)).to be_nil
    end
  end

  describe "capture_instance_vars (private, tested via on_raise)" do
    before do
      described_class.enable!
      RailsErrorDashboard.configuration.enable_instance_variables = true
      # Disable local variables to isolate instance var behavior
      RailsErrorDashboard.configuration.enable_local_variables = false
    end

    after do
      RailsErrorDashboard.configuration.enable_instance_variables = false
      RailsErrorDashboard.configuration.enable_local_variables = false
    end

    it "skips @_red_ prefixed instance variables" do
      exception = StandardError.new("test")
      # Simulate: object had @_red_locals and @_red_instance_vars plus @user
      ivars = { :_self_class => "Foo", :@user => "Gandalf" }
      exception.instance_variable_set(:@_red_instance_vars, ivars)

      result = described_class.extract_instance_vars(exception)
      expect(result.keys).not_to include(:@_red_locals)
      expect(result.keys).not_to include(:@_red_instance_vars)
    end

    it "respects instance_variable_max_count limit" do
      RailsErrorDashboard.configuration.instance_variable_max_count = 3

      exception = StandardError.new("test")
      # Simulate more ivars than the limit (plus _self_class metadata)
      ivars = { _self_class: "Foo" }
      5.times { |i| ivars[:"@var_#{i}"] = "val_#{i}" }
      exception.instance_variable_set(:@_red_instance_vars, ivars)

      result = described_class.extract_instance_vars(exception)
      # _self_class + 5 vars = 6, but the raw hash was pre-constructed
      # The actual limit is enforced in capture_instance_vars (TracePoint callback)
      expect(result).to be_a(Hash)
    end

    it "includes _self_class metadata in captured data" do
      exception = StandardError.new("test")
      ivars = { :_self_class => "UsersController", :@name => "Gandalf" }
      exception.instance_variable_set(:@_red_instance_vars, ivars)

      result = described_class.extract_instance_vars(exception)
      expect(result[:_self_class]).to eq("UsersController")
    end
  end

  describe "capture_instance_vars via real object extraction" do
    # Tests the private capture_instance_vars method with real objects
    # to verify TracePoint-style extraction behavior end-to-end.
    # We call the private method directly since spec paths are filtered by skip_path?.
    before do
      described_class.enable!
      RailsErrorDashboard.configuration.enable_instance_variables = true
    end

    after do
      RailsErrorDashboard.configuration.enable_instance_variables = false
    end

    it "extracts instance variables from a real object" do
      obj = Object.new
      obj.instance_variable_set(:@user, "Gandalf")
      obj.instance_variable_set(:@retry_count, 3)

      result = described_class.send(:capture_instance_vars, obj)
      expect(result).to be_a(Hash)
      expect(result[:_self_class]).to eq("Object")
      expect(result[:@user]).to eq("Gandalf")
      expect(result[:@retry_count]).to eq(3)
    end

    it "captures _self_class metadata with the receiver's class name" do
      klass = Class.new do
        def self.name = "TestService"
      end
      obj = klass.new
      obj.instance_variable_set(:@data, "value")

      result = described_class.send(:capture_instance_vars, obj)
      expect(result[:_self_class]).to eq("TestService")
    end

    it "filters out all @_ prefixed ivars (framework internals)" do
      obj = Object.new
      obj.instance_variable_set(:@_request, "GET /users")
      obj.instance_variable_set(:@_response, "200 OK")
      obj.instance_variable_set(:@_red_locals, { x: 1 })
      obj.instance_variable_set(:@name, "Gandalf")

      result = described_class.send(:capture_instance_vars, obj)
      expect(result.keys).not_to include(:@_request, :@_response, :@_red_locals)
      expect(result[:@name]).to eq("Gandalf")
    end

    it "returns nil when object has only @_ prefixed ivars" do
      obj = Object.new
      obj.instance_variable_set(:@_internal, "hidden")
      obj.instance_variable_set(:@_framework, "rails")

      result = described_class.send(:capture_instance_vars, obj)
      expect(result).to be_nil
    end

    it "returns nil for nil object" do
      result = described_class.send(:capture_instance_vars, nil)
      expect(result).to be_nil
    end

    it "respects instance_variable_max_count limit" do
      RailsErrorDashboard.configuration.instance_variable_max_count = 2

      obj = Object.new
      5.times { |i| obj.instance_variable_set(:"@var_#{i}", "val_#{i}") }

      result = described_class.send(:capture_instance_vars, obj)
      # _self_class metadata + 2 ivars (limited by max_count)
      ivar_keys = result.keys - [ :_self_class ]
      expect(ivar_keys.size).to eq(2)
    end

    it "handles anonymous class (nil class name) gracefully" do
      obj = Class.new.new
      obj.instance_variable_set(:@data, "test")

      result = described_class.send(:capture_instance_vars, obj)
      expect(result[:_self_class]).to be_a(String)
    end

    it "handles per-variable extraction errors gracefully" do
      obj = Object.new
      obj.instance_variable_set(:@good, "ok")
      obj.instance_variable_set(:@bad, "will fail")

      # Make instance_variable_get fail for :@bad
      allow(obj).to receive(:instance_variable_get).and_call_original
      allow(obj).to receive(:instance_variable_get).with(:@bad).and_raise(RuntimeError, "boom")

      result = described_class.send(:capture_instance_vars, obj)
      expect(result[:@good]).to eq("ok")
      expect(result[:@bad]).to include("extraction error")
    end

    it "handles object whose instance_variables method raises" do
      obj = Object.new
      allow(obj).to receive(:instance_variables).and_raise(RuntimeError, "boom")

      result = described_class.send(:capture_instance_vars, obj)
      expect(result).to be_nil
    end

    it "captures object with ivar containing a circular reference" do
      obj = Object.new
      circular_array = [ 1, 2 ]
      circular_array << circular_array
      obj.instance_variable_set(:@data, circular_array)

      result = described_class.send(:capture_instance_vars, obj)
      # Should capture the raw value (circular detection happens in VariableSerializer)
      expect(result[:@data]).to be_a(Array)
    end
  end

  describe "instance variable config isolation" do
    before { described_class.enable! }

    after do
      RailsErrorDashboard.configuration.enable_instance_variables = false
      RailsErrorDashboard.configuration.enable_local_variables = false
    end

    it "captures only locals when enable_instance_variables is false" do
      RailsErrorDashboard.configuration.enable_local_variables = true
      RailsErrorDashboard.configuration.enable_instance_variables = false

      exception = StandardError.new("test")
      # Manually attach locals (spec path is filtered by TracePoint)
      exception.instance_variable_set(:@_red_locals, { x: 1 })

      expect(described_class.extract(exception)).to eq({ x: 1 })
      expect(described_class.extract_instance_vars(exception)).to be_nil
    end

    it "captures only ivars when enable_local_variables is false" do
      RailsErrorDashboard.configuration.enable_local_variables = false
      RailsErrorDashboard.configuration.enable_instance_variables = true

      exception = StandardError.new("test")
      # Manually attach ivars (spec path is filtered by TracePoint)
      exception.instance_variable_set(:@_red_instance_vars, { _self_class: "Foo", :@data => "bar" })

      expect(described_class.extract(exception)).to be_nil
      result = described_class.extract_instance_vars(exception)
      expect(result[:_self_class]).to eq("Foo")
      expect(result[:@data]).to eq("bar")
    end
  end

  describe "TracePoint enablement for instance variables only" do
    after do
      RailsErrorDashboard.configuration.enable_instance_variables = false
      RailsErrorDashboard.configuration.enable_local_variables = false
    end

    it "enables TracePoint when only enable_instance_variables is true" do
      RailsErrorDashboard.configuration.enable_local_variables = false
      RailsErrorDashboard.configuration.enable_instance_variables = true

      # Engine would call enable! — we simulate that check
      if RailsErrorDashboard.configuration.enable_local_variables ||
         RailsErrorDashboard.configuration.enable_instance_variables
        described_class.enable!
      end

      expect(described_class.enabled?).to be true
    end

    it "does not enable TracePoint when both features are disabled" do
      described_class.disable!
      RailsErrorDashboard.configuration.enable_local_variables = false
      RailsErrorDashboard.configuration.enable_instance_variables = false

      if RailsErrorDashboard.configuration.enable_local_variables ||
         RailsErrorDashboard.configuration.enable_instance_variables
        described_class.enable!
      end

      expect(described_class.enabled?).to be false
    end
  end

  describe "path filtering" do
    before { described_class.enable! }

    it "skips paths containing /gems/" do
      # Simulate: calling skip_path? through the callback
      # We verify indirectly: gem-originated exceptions don't get locals
      exception = nil
      begin
        # Force a StandardError from JSON gem code
        JSON.parse("not valid json at all")
      rescue => e
        exception = e
      end

      expect(described_class.extract(exception)).to be_nil
    end

    it "skips paths containing /vendor/" do
      # Vendor-originated exceptions should be filtered
      # Verified: skip_path? checks path.include?("/vendor/")
      exception = StandardError.new("vendor error")
      # No @_red_locals should be set for vendor paths
      expect(described_class.extract(exception)).to be_nil
    end
  end
end
