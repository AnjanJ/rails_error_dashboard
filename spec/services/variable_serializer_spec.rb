# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::VariableSerializer do
  before do
    allow(RailsErrorDashboard).to receive(:configuration).and_return(config)
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
  end

  let(:config) do
    RailsErrorDashboard::Configuration.new.tap do |c|
      c.enable_local_variables = true
      c.local_variable_max_count = 15
      c.local_variable_max_depth = 3
      c.local_variable_max_string_length = 200
      c.local_variable_max_array_items = 10
      c.local_variable_max_hash_items = 20
      c.local_variable_filter_patterns = []
      c.filter_sensitive_data = true
      c.sensitive_data_patterns = []
    end
  end

  describe ".call" do
    it "returns empty hash for nil input" do
      expect(described_class.call(nil)).to eq({})
    end

    it "returns empty hash for empty hash" do
      expect(described_class.call({})).to eq({})
    end

    it "returns empty hash for non-hash input" do
      expect(described_class.call("not a hash")).to eq({})
    end

    it "serializes nil value" do
      result = described_class.call({ x: nil })
      expect(result["x"][:type]).to eq("NilClass")
      expect(result["x"][:value]).to be_nil
      expect(result["x"][:truncated]).to be false
    end

    it "serializes boolean values" do
      result = described_class.call({ flag: true, off: false })
      expect(result["flag"][:type]).to eq("TrueClass")
      expect(result["flag"][:value]).to be true
      expect(result["off"][:value]).to be false
    end

    it "serializes integer values" do
      result = described_class.call({ count: 42 })
      expect(result["count"][:type]).to eq("Integer")
      expect(result["count"][:value]).to eq(42)
    end

    it "serializes float values" do
      result = described_class.call({ price: 19.99 })
      expect(result["price"][:type]).to eq("Float")
      expect(result["price"][:value]).to eq(19.99)
    end

    it "serializes symbol values" do
      result = described_class.call({ status: :active })
      expect(result["status"][:type]).to eq("Symbol")
      expect(result["status"][:value]).to eq("active")
    end

    it "serializes short strings without truncation" do
      result = described_class.call({ name: "hello" })
      expect(result["name"][:type]).to eq("String")
      expect(result["name"][:value]).to eq("hello")
      expect(result["name"][:truncated]).to be false
    end

    it "truncates long strings" do
      long_str = "x" * 300
      result = described_class.call({ data: long_str })
      expect(result["data"][:value].length).to eq(200)
      expect(result["data"][:truncated]).to be true
    end

    it "serializes arrays" do
      result = described_class.call({ items: [ 1, 2, 3 ] })
      expect(result["items"][:type]).to eq("Array")
      expect(result["items"][:value]).to eq([ 1, 2, 3 ])
      expect(result["items"][:truncated]).to be false
    end

    it "truncates large arrays" do
      result = described_class.call({ items: (1..20).to_a })
      expect(result["items"][:value].length).to eq(10)
      expect(result["items"][:truncated]).to be true
    end

    it "serializes hashes" do
      result = described_class.call({ opts: { a: 1, b: 2 } })
      expect(result["opts"][:type]).to eq("Hash")
      expect(result["opts"][:value]).to eq({ "a" => 1, "b" => 2 })
    end

    it "truncates large hashes" do
      large_hash = (1..30).each_with_object({}) { |i, h| h["k#{i}"] = i }
      result = described_class.call({ data: large_hash })
      expect(result["data"][:value].length).to eq(20)
      expect(result["data"][:truncated]).to be true
    end

    it "detects circular references in arrays" do
      arr = [ 1, 2 ]
      arr << arr
      result = described_class.call({ loop: arr })
      expect(result["loop"][:value]).to include("(circular reference)")
    end

    it "detects circular references in hashes" do
      h = { a: 1 }
      h[:self] = h
      result = described_class.call({ loop: h })
      expect(result["loop"][:value]["self"]).to eq("(circular reference)")
    end

    it "respects depth limits" do
      nested = { a: { b: { c: { d: "deep" } } } }
      result = described_class.call({ data: nested })
      expect(result["data"][:value]["a"]["b"]["c"]).to eq("(depth limit reached)")
    end

    it "handles IO objects safely" do
      result = described_class.call({ file: $stdout })
      expect(result["file"][:value]).to match(/#<IO>/)
    end

    it "handles Proc objects safely" do
      result = described_class.call({ block: -> { "test" } })
      expect(result["block"][:value]).to eq("#<Proc>")
    end

    it "handles Class objects" do
      result = described_class.call({ klass: String })
      expect(result["klass"][:value]).to eq("String")
    end

    it "handles Regexp objects" do
      result = described_class.call({ pattern: /\d+/ })
      expect(result["pattern"][:value]).to eq("/\\d+/")
    end

    it "handles Range objects" do
      result = described_class.call({ range: 1..10 })
      expect(result["range"][:value]).to eq("1..10")
    end

    context "sensitive variable filtering" do
      it "filters variables with sensitive names" do
        result = described_class.call({ user_password: "secret123", name: "John" })
        expect(result["user_password"][:value]).to eq("[FILTERED]")
        expect(result["user_password"][:filtered]).to be true
        expect(result["name"][:value]).to eq("John")
      end

      it "filters token variables" do
        result = described_class.call({ auth_token: "abc123" })
        expect(result["auth_token"][:value]).to eq("[FILTERED]")
        expect(result["auth_token"][:filtered]).to be true
      end

      it "filters api_key variables" do
        result = described_class.call({ api_key: "sk-123" })
        expect(result["api_key"][:value]).to eq("[FILTERED]")
      end

      it "filters nested hash keys matching sensitive patterns" do
        result = described_class.call({ opts: { password: "s3cret!", name: "John" } })
        expect(result["opts"][:value]["password"]).to eq("[FILTERED]")
        expect(result["opts"][:value]["name"]).to eq("John")
      end

      it "filters deeply nested sensitive hash keys" do
        result = described_class.call({ config: { db: { secret_key: "abc", host: "localhost" } } })
        expect(result["config"][:value]["db"]["secret_key"]).to eq("[FILTERED]")
        expect(result["config"][:value]["db"]["host"]).to eq("localhost")
      end

      # Rails' own filter semantics, which the examples above never exercise:
      # every pattern here is a FLAT name that matches at any depth. A dotted
      # pattern is a PATH, and it only matches when the filter sees the whole
      # tree -- so the variable's own name has to be part of that tree. Passing
      # just the inner hash silently dropped the outer key, and the same value
      # Rails redacts in request params stayed readable in captured locals.
      context "with a dotted filter_parameters pattern" do
        around do |example|
          original = Rails.application.config.filter_parameters
          Rails.application.config.filter_parameters = [ "profile.private_note" ]
          RailsErrorDashboard::Services::SensitiveDataFilter.reset!
          example.run
        ensure
          Rails.application.config.filter_parameters = original
          RailsErrorDashboard::Services::SensitiveDataFilter.reset!
        end

        it "redacts the value at the dotted path, under the variable's own name" do
          result = described_class.call({ profile: { private_note: "SYNTHETIC_SECRET", public: "ok" } })

          expect(result["profile"][:value]["private_note"]).to eq("[FILTERED]")
          expect(result["profile"][:value]["public"]).to eq("ok")
        end

        it "applies the same path semantics to instance variables" do
          # Instance variables reach the same filter_serialized entry point, and
          # carry an @ prefix that must not break the path match.
          result = described_class.call(
            { "@profile" => { private_note: "SYNTHETIC_SECRET" } },
            additional_filter_patterns: [ "@profile.private_note" ]
          )

          expect(result["@profile"][:value]["private_note"]).to eq("[FILTERED]")
        end

        it "leaves the same key alone under a different variable name" do
          # profile.private_note is a path, not a name: private_note under
          # `other` is a different path and must survive, exactly as it does
          # for request params.
          result = described_class.call({ other: { private_note: "KEEP_ME" } })

          expect(result["other"][:value]["private_note"]).to eq("KEEP_ME")
        end

        # REQ-F4: nothing may observe a value that carries display metadata but
        # has not been filtered. The pipeline is serialize -> filter -> return,
        # and `type`/`truncated` are SIBLINGS of `value`, never wrapped around
        # it, so the filter always receives the raw structure. Asserted here
        # rather than assumed, because the whole R6 class of bug came from the
        # filter seeing something other than what it needed to see.
        it "returns no variable whose value is unfiltered but already labelled" do
          result = described_class.call(
            { profile: [ { private_note: "SYNTHETIC_SECRET" } ], other: { ok: "fine" } }
          )

          result.each_value do |info|
            expect(info).to have_key(:type)
            expect(info).to have_key(:truncated)
            expect(info[:value].to_s).not_to include("SYNTHETIC_SECRET")
          end
        end

        # The contract is PARITY WITH RAILS, not maximal redaction. Each
        # expectation below is what ActiveSupport::ParameterFilter itself does
        # to the same structure in request params -- verified by running it,
        # not assumed. Over-redaction is a defect on the same footing as
        # under-redaction: it silently destroys data a developer needs.
        #
        # The array row is the R6 leak: the previous fix wrapped Hash values
        # under the variable name and sent Array values straight to the
        # recursive walker, dropping the "profile" path segment.
        describe "parity with ActiveSupport::ParameterFilter" do
          def rails_result(structure)
            ActiveSupport::ParameterFilter
              .new([ "profile.private_note" ])
              .filter("profile" => structure)["profile"]
          end

          {
            "a hash" => { private_note: "SYNTHETIC_SECRET" },
            "an array of hashes" => [ { private_note: "SYNTHETIC_SECRET" } ],
            "a nested array of hashes" => [ [ { private_note: "SYNTHETIC_SECRET" } ] ]
          }.each do |shape, value|
            it "redacts #{shape}, as Rails does" do
              result = described_class.call({ profile: value })

              expect(result["profile"][:value].to_s).not_to include("SYNTHETIC_SECRET")
              expect(result["profile"][:value].to_s).to include("[FILTERED]")
              # And the shape is preserved, not collapsed.
              expect(result["profile"][:value].class).to eq(value.class)
            end
          end

          # These paths do NOT match, so the secret must survive filtering.
          # Depth limiting is a separate concern and would mask the assertion,
          # so the nested case is given headroom via local_variable_max_depth.
          {
            "a hash under an intermediate key" => { list: [ { private_note: "SYNTHETIC_SECRET" } ] },
            "a scalar" => "SYNTHETIC_SECRET"
          }.each do |shape, value|
            it "leaves #{shape} alone, because Rails does not match that path" do
              # profile.list.private_note and profile are DIFFERENT paths from
              # profile.private_note. Redacting here would exceed Rails.
              expect(rails_result(value).to_s).to include("SYNTHETIC_SECRET")

              RailsErrorDashboard.configuration.local_variable_max_depth = 6
              result = described_class.call({ profile: value })

              expect(result["profile"][:value].to_s).to include("SYNTHETIC_SECRET")
            end
          end
        end

        it "redacts an array-valued instance variable under its @-prefixed name" do
          # Instance variables reach the same entry point with an @ prefix that
          # must not break the path match -- and the array shape is the one
          # that leaked.
          result = described_class.call(
            { "@profile" => [ { private_note: "SYNTHETIC_SECRET" } ] },
            additional_filter_patterns: [ "@profile.private_note" ]
          )

          expect(result["@profile"][:value].to_s).not_to include("SYNTHETIC_SECRET")
        end

        it "applies a Regexp pattern to an array-valued variable" do
          result = described_class.call(
            { profile: [ { private_note: "SYNTHETIC_SECRET" } ] },
            additional_filter_patterns: [ /private_note/ ]
          )

          expect(result["profile"][:value].to_s).not_to include("SYNTHETIC_SECRET")
        end

        it "hands a Proc pattern the key and value, not a synthesized dotted path" do
          # ParameterFilter calls a Proc with (key, value) -- or
          # (key, value, original_params) for a 3-arity Proc. Wrapping under the
          # variable name preserves that contract precisely BECAUSE
          # ParameterFilter does the walking; hand-rolled path matching could
          # not emulate it.
          seen = []
          proc_filter = lambda do |key, value|
            seen << key
            value.replace("[FILTERED]") if key == "private_note" && value.is_a?(String)
          end

          result = described_class.call(
            { profile: [ { private_note: +"SYNTHETIC_SECRET" } ] },
            additional_filter_patterns: [ proc_filter ]
          )

          expect(seen).to include("private_note")
          expect(seen).not_to include("profile.private_note")
          expect(result["profile"][:value].to_s).not_to include("SYNTHETIC_SECRET")
        end

        it "redacts a nested path when the pattern actually names it" do
          # Same structure as the negative case above; only the pattern differs.
          Rails.application.config.filter_parameters = [ "profile.list.private_note" ]
          RailsErrorDashboard::Services::SensitiveDataFilter.reset!
          RailsErrorDashboard.configuration.local_variable_max_depth = 6

          result = described_class.call({ profile: { list: [ { private_note: "SYNTHETIC_SECRET" } ] } })

          expect(result["profile"][:value].to_s).not_to include("SYNTHETIC_SECRET")
        end
      end

      it "filters sensitive keys inside arrays of hashes" do
        result = described_class.call({ users: [ { name: "John", password: "secret" } ] })
        expect(result["users"][:value].first["password"]).to eq("[FILTERED]")
        expect(result["users"][:value].first["name"]).to eq("John")
      end

      it "honors Regexp patterns from Rails filter_parameters" do
        allow(Rails).to receive_message_chain(:application, :config, :filter_parameters)
          .and_return([ /custom_secret/ ])
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!

        result = described_class.call({ my_custom_secret_value: "hidden", name: "visible" })
        expect(result["my_custom_secret_value"][:value]).to eq("[FILTERED]")
        expect(result["name"][:value]).to eq("visible")
      end

      it "honors Regexp patterns for nested hash keys" do
        allow(Rails).to receive_message_chain(:application, :config, :filter_parameters)
          .and_return([ /^api_/ ])
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!

        result = described_class.call({ opts: { api_credential: "xyz", name: "ok" } })
        expect(result["opts"][:value]["api_credential"]).to eq("[FILTERED]")
        expect(result["opts"][:value]["name"]).to eq("ok")
      end

      it "scrubs credit card numbers from string values" do
        result = described_class.call({ note: "Card is 4111 1111 1111 1111 on file" })
        expect(result["note"][:value]).not_to include("4111")
        expect(result["note"][:value]).to include("[FILTERED]")
      end

      it "scrubs credit card numbers from nested string values" do
        result = described_class.call({ data: { memo: "CC 4111-1111-1111-1111" } })
        expect(result["data"][:value]["memo"]).not_to include("4111")
      end

      it "uses custom local_variable_filter_patterns" do
        config.local_variable_filter_patterns = [ "internal_id" ]
        result = described_class.call({ internal_id: "12345", name: "test" })
        expect(result["internal_id"][:value]).to eq("[FILTERED]")
        expect(result["name"][:value]).to eq("test")
      end

      it "applies local_variable_filter_patterns to nested hash keys" do
        config.local_variable_filter_patterns = [ "tracking_code" ]
        result = described_class.call({ opts: { tracking_code: "abc", label: "ok" } })
        expect(result["opts"][:value]["tracking_code"]).to eq("[FILTERED]")
        expect(result["opts"][:value]["label"]).to eq("ok")
      end

      it "skips filtering when filter_sensitive_data is false" do
        config.filter_sensitive_data = false
        result = described_class.call({ password: "secret", api_key: "sk-123" })
        expect(result["password"][:value]).to eq("secret")
        expect(result["api_key"][:value]).to eq("sk-123")
      end

      it "never raises even if filtering fails" do
        allow(RailsErrorDashboard::Services::SensitiveDataFilter).to receive(:parameter_filter)
          .and_raise(RuntimeError, "boom")
        result = described_class.call({ name: "test" })
        expect(result).to have_key("name")
      end
    end

    context "filtering deep dive" do
      it "handles empty hash value inside a variable" do
        result = described_class.call({ opts: {} })
        expect(result["opts"][:type]).to eq("Hash")
        expect(result["opts"][:value]).to eq({})
      end

      it "preserves nil values inside nested hashes while filtering keys" do
        result = described_class.call({ opts: { password: "secret", data: nil, name: "ok" } })
        expect(result["opts"][:value]["password"]).to eq("[FILTERED]")
        expect(result["opts"][:value]["name"]).to eq("ok")
      end

      it "serializes unicode variable names without error" do
        result = described_class.call({ "名前" => "value", "emoji_🎉" => "party" })
        expect(result).to have_key("名前")
        expect(result["名前"][:value]).to eq("value")
        expect(result).to have_key("emoji_🎉")
      end

      it "serializes unicode string values" do
        result = described_class.call({ greeting: "こんにちは世界" })
        expect(result["greeting"][:value]).to eq("こんにちは世界")
      end

      it "handles depth limit interacting with sensitive key filtering" do
        # At max depth, value becomes "(depth limit reached)" string
        nested = { a: { b: { c: { password: "secret" } } } }
        result = described_class.call({ data: nested })
        # c is at depth 3 (0-indexed: data=0, a=1, b=2, c=3) — hits depth limit
        expect(result["data"][:value]["a"]["b"]["c"]).to eq("(depth limit reached)")
      end

      it "filters sensitive keys in mixed-type arrays" do
        result = described_class.call({
          items: [ 42, "hello", { token: "secret", safe: "ok" }, true ]
        })
        values = result["items"][:value]
        expect(values[0]).to eq(42)
        expect(values[1]).to eq("hello")
        expect(values[2]["token"]).to eq("[FILTERED]")
        expect(values[2]["safe"]).to eq("ok")
        expect(values[3]).to be true
      end

      it "handles variable names with regex special characters" do
        result = described_class.call({ "var[0]" => "value", "obj.attr" => "test" })
        expect(result).to have_key("var[0]")
        expect(result["var[0]"][:value]).to eq("value")
        expect(result).to have_key("obj.attr")
      end

      it "returns unfiltered result when parameter_filter returns nil" do
        allow(RailsErrorDashboard::Services::SensitiveDataFilter).to receive(:parameter_filter)
          .and_return(nil)
        result = described_class.call({ password: "visible", name: "test" })
        # With nil filter, no filtering applied — raw values returned
        expect(result["password"][:value]).to eq("visible")
        expect(result["name"][:value]).to eq("test")
      end

      it "falls back to base filter when effective_filter raises during pattern building" do
        # Force effective_filter to raise by making config access blow up
        allow(RailsErrorDashboard.configuration).to receive(:local_variable_filter_patterns)
          .and_raise(RuntimeError, "config boom")
        # Should fall back to SensitiveDataFilter.parameter_filter (base filter)
        result = described_class.call({ password: "secret", name: "test" })
        expect(result["password"][:value]).to eq("[FILTERED]")
        expect(result["name"][:value]).to eq("test")
      end

      it "handles multiple sensitive patterns matching the same variable" do
        # "api_secret_token" matches :api_secret, :secret, :token all at once
        result = described_class.call({ api_secret_token: "multi-match" })
        expect(result["api_secret_token"][:value]).to eq("[FILTERED]")
        expect(result["api_secret_token"][:filtered]).to be true
      end

      it "combines sensitive_data_patterns config with default patterns" do
        config.sensitive_data_patterns = [ :custom_field ]
        RailsErrorDashboard::Services::SensitiveDataFilter.reset!

        result = described_class.call({ custom_field: "hidden", name: "visible" })
        expect(result["custom_field"][:value]).to eq("[FILTERED]")
        expect(result["name"][:value]).to eq("visible")
      end

      it "uses base filter when local_variable_filter_patterns is empty (default)" do
        config.local_variable_filter_patterns = []
        result = described_class.call({ password: "secret", name: "ok" })
        expect(result["password"][:value]).to eq("[FILTERED]")
        expect(result["name"][:value]).to eq("ok")
      end

      it "scrubs credit card patterns in deeply nested string values" do
        result = described_class.call({
          data: [ { notes: [ "CC: 4111-1111-1111-1111" ] } ]
        })
        nested_str = result["data"][:value].first["notes"].first
        expect(nested_str).not_to include("4111")
      end

      it "filters key=value patterns in string values" do
        result = described_class.call({ log_line: "auth password=hunter2 status=ok" })
        expect(result["log_line"][:value]).not_to include("hunter2")
        expect(result["log_line"][:value]).to include("status=ok")
      end
    end

    context "adversarial inputs" do
      it "handles very long variable names" do
        long_name = ("a" * 500).to_sym
        result = described_class.call({ long_name => "value" })
        expect(result[long_name.to_s][:value]).to eq("value")
      end

      it "handles empty string variable name" do
        result = described_class.call({ "" => "value" })
        expect(result[""]).not_to be_nil
      end

      it "handles frozen strings" do
        result = described_class.call({ data: "frozen".freeze })
        expect(result["data"][:value]).to eq("frozen")
      end

      it "handles binary string data without crashing" do
        binary = "\x00\xFF\xFE binary data".dup.force_encoding("BINARY")
        result = described_class.call({ raw: binary })
        expect(result["raw"][:type]).to eq("String")
        expect(result).to have_key("raw")
      end

      it "handles Struct objects via inspect fallback" do
        klass = Struct.new(:name, :age)
        obj = klass.new("Alice", 30)
        result = described_class.call({ person: obj })
        expect(result["person"][:value]).to include("Alice")
      end

      # inspect on an unknown object is arbitrary APPLICATION code running on
      # the failure path. Truncating its output to 200 characters bounds what
      # is stored, not what it costs: an object whose inspect is slow or
      # allocates a megabyte pays that in full before a single character is
      # discarded. The default is now a safe structural summary, with full
      # inspect available per type by opt-in.
      it "does not call inspect on an unknown object by default" do
        expensive = Object.new
        called = false
        expensive.define_singleton_method(:inspect) do
          called = true
          "x" * 1_000_000
        end

        result = described_class.call({ thing: expensive })

        expect(called).to be(false)
        expect(result["thing"][:value]).to include("#<Object")
      end

      it "calls inspect for a type the host app opted in to" do
        klass = Struct.new(:name)
        config.local_variable_inspect_allowlist = [ "Struct" ]

        result = described_class.call({ person: klass.new("Alice") })

        expect(result["person"][:value]).to include("Alice")
      end

      # A budget, so even an allowlisted type cannot stall the failure path.
      it "falls back to a safe summary when inspect exceeds its budget" do
        slow = Object.new
        slow.define_singleton_method(:inspect) do
          sleep 0.05
          "slow value"
        end
        config.local_variable_inspect_allowlist = [ "Object" ]
        config.local_variable_inspect_budget_ms = 1

        result = described_class.call({ slow: slow })

        expect(result["slow"][:value]).to include("#<Object")
      end

      it "handles object whose inspect raises" do
        bad_obj = Object.new
        def bad_obj.inspect; raise "nope"; end
        result = described_class.call({ bad: bad_obj })
        expect(result["bad"][:value]).to include("#<")
      end

      it "handles concurrent calls from multiple threads" do
        results = Array.new(5)
        threads = 5.times.map do |i|
          Thread.new do
            results[i] = described_class.call({ "var_#{i}" => i })
          end
        end
        threads.each(&:join)

        results.each_with_index do |result, i|
          expect(result["var_#{i}"][:value]).to eq(i)
        end
      end
    end

    it "respects max_count limit (defaults to local_variable_max_count)" do
      locals = (1..20).each_with_object({}) { |i, h| h[:"var_#{i}"] = i }
      result = described_class.call(locals)
      expect(result.size).to eq(15)
    end

    it "respects caller-specified max_count over default" do
      vars = (1..25).each_with_object({}) { |i, h| h[:"var_#{i}"] = i }
      result = described_class.call(vars, max_count: 20)
      expect(result.size).to eq(20)
    end

    it "uses local_variable_max_count when no max_count specified" do
      config.local_variable_max_count = 5
      vars = (1..10).each_with_object({}) { |i, h| h[:"var_#{i}"] = i }
      result = described_class.call(vars)
      expect(result.size).to eq(5)
    end

    context "instance variable serialization" do
      it "serializes @-prefixed keys as strings" do
        ivars = { :@user => "Gandalf", :@count => 42 }
        result = described_class.call(ivars)
        expect(result).to have_key("@user")
        expect(result).to have_key("@count")
        expect(result["@user"][:value]).to eq("Gandalf")
        expect(result["@count"][:value]).to eq(42)
      end

      it "serializes _self_class metadata correctly" do
        ivars = { _self_class: "UsersController", :@name => "Gandalf" }
        result = described_class.call(ivars)
        expect(result["_self_class"][:type]).to eq("String")
        expect(result["_self_class"][:value]).to eq("UsersController")
        expect(result["_self_class"][:truncated]).to be false
      end

      it "applies additional_filter_patterns to instance variable names" do
        ivars = { :@secret_key => "abc123", :@name => "Gandalf" }
        result = described_class.call(ivars, additional_filter_patterns: [ /secret/ ])
        expect(result["@secret_key"][:value]).to eq("[FILTERED]")
        expect(result["@secret_key"][:filtered]).to be true
        expect(result["@name"][:value]).to eq("Gandalf")
      end

      it "works with empty additional_filter_patterns" do
        ivars = { :@name => "Gandalf" }
        result = described_class.call(ivars, additional_filter_patterns: [])
        expect(result["@name"][:value]).to eq("Gandalf")
      end

      it "applies max_count before filtering" do
        ivars = {}
        25.times { |i| ivars[:"@var_#{i}"] = "val_#{i}" }
        result = described_class.call(ivars, max_count: 10)
        expect(result.size).to eq(10)
      end
    end

    it "handles per-variable errors gracefully" do
      bad_obj = Object.new
      def bad_obj.class; raise "boom"; end
      result = described_class.call({ good: "ok", bad: bad_obj })
      expect(result["good"][:value]).to eq("ok")
      expect(result).to have_key("bad")
    end

    it "cleans up thread-local state in ensure" do
      described_class.call({ x: 1 })
      expect(Thread.current[described_class::THREAD_KEY]).to be_nil
    end

    it "cleans up thread-local state even when serialization fails internally" do
      Thread.current[described_class::THREAD_KEY] = Set.new([ 999 ])
      described_class.call({ x: 1 })
      expect(Thread.current[described_class::THREAD_KEY]).to be_nil
    end
  end
end
