# frozen_string_literal: true

require "rails_helper"

# The engine's middleware initializer, run against stand-ins: the real engine
# stack is memoised once built, so this never touches it.
#
# In an API-only host the dashboard's session must live on the engine's own
# stack. On the host's stack it reached every API endpoint: a host action that
# wrote the session got a cookie instead of Rails' DisabledSessionError.
RSpec.describe "The engine's middleware initializer" do
  let(:recorder_class) do
    Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      %i[use insert_before insert_after unshift].each do |name|
        define_method(name) { |*args, **_options| @calls << [ name, *args ] }
      end

      def added
        calls.flat_map { |call| call.drop(1) }
      end
    end
  end

  let(:host_stack) { recorder_class.new }
  let(:host_config_stack) { recorder_class.new }
  let(:engine_stack) { recorder_class.new }
  let(:app) do
    double("host app", middleware: host_stack,
      config: double("host config", api_only: api_only, middleware: host_config_stack))
  end
  let(:engine) { double("engine", config: double("engine config", middleware: engine_stack)) }

  let(:session_middleware) do
    [
      ActionDispatch::Flash, ActionDispatch::Cookies, ActionDispatch::Session::CookieStore,
      RailsErrorDashboard::Middleware::DashboardSession
    ]
  end

  def run_initializer
    initializer = RailsErrorDashboard::Engine.initializers.find { |i| i.name == "rails_error_dashboard.middleware" }
    initializer.bind(engine).run(app)
  end

  context "in an API-only host" do
    let(:api_only) { true }

    # host-hygiene-0-17/REQ-1
    it "adds no cookie, session or flash middleware to the host's stack" do
      run_initializer

      expect((host_stack.added + host_config_stack.added) & session_middleware).to be_empty
    end

    # host-hygiene-0-17/REQ-2
    it "puts the dashboard's session middleware on the engine's own stack" do
      run_initializer

      expect(engine_stack.calls).to eq([ [ :use, RailsErrorDashboard::Middleware::DashboardSession ] ])
    end
  end

  context "in a full-stack host, which has its own session" do
    let(:api_only) { false }

    it "adds session middleware nowhere" do
      run_initializer

      expect((host_stack.added + host_config_stack.added + engine_stack.added) & session_middleware).to be_empty
    end
  end
end
