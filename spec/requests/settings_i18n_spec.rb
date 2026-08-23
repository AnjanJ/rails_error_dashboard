# frozen_string_literal: true

require "rails_helper"

# The settings page (P2-T8). It is data-driven rather than a normal template:
# a hash of 72 config options keyed by the option's own name. The risk is the
# (a)/(b) split — the prose describing a setting is translated, the config
# identifiers, file paths, env vars, rake commands and Ruby APIs beside it are
# not. These pin that boundary.
RSpec.describe "Settings translations", type: :request do
  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  def body_doc
    Nokogiri::HTML(response.body)
  end

  describe "page chrome" do
    it "renders the title and version" do
      get "/error_dashboard/settings"

      expect(response).to have_http_status(:ok)
      expect(body_doc.at_css("h1").text.strip).to eq("Settings")
      expect(response.body).to include("v#{RailsErrorDashboard::VERSION}")
    end

    # The sentence wraps a <code> element. It must stay one key with the path
    # interpolated, and the path must render as markup rather than escaped text.
    it "renders the intro sentence around the initializer path" do
      get "/error_dashboard/settings"

      expect(response.body).to include("<code>config/initializers/rails_error_dashboard.rb</code>")
      expect(response.body).to include("Read-only view of current configuration.")
      expect(response.body).not_to include("&lt;code&gt;config/initializers")
    end

    # Two sentences, one wrapping <code> and one wrapping the docs <a>. They are
    # separate keys so each stays a whole sentence, and the line break between
    # them is preserved — extraction is a refactor, not a redesign.
    it "renders the help footer with a working documentation link" do
      get "/error_dashboard/settings"

      link = body_doc.at_css("a.alert-link")
      expect(link).to be_present
      expect(link.text).to eq("documentation")
      expect(link["href"]).to eq("https://github.com/AnjanJ/rails_error_dashboard")
      expect(response.body).to include("Need to change these settings?")
      expect(response.body).to include("and restart your application.")
    end

    it "keeps the line break between the two help sentences" do
      get "/error_dashboard/settings"

      expect(body_doc.at_css("div.alert p br")).to be_present
    end
  end

  describe "setting groups" do
    it "renders every group heading" do
      get "/error_dashboard/settings"

      text = response.body
      [ "Core Features", "Multi-App Support", "Notification Channels",
        "Deep Debugging", "Internal Logging" ].each do |heading|
        expect(text).to include(heading)
      end
    end

    # The option count was a bare "N options" with no plural handling.
    it "pluralizes the per-group option count" do
      get "/error_dashboard/settings"

      # System Health has exactly one option, so it exercises the singular.
      expect(response.body).to include("1 option<")
      expect(response.body).to include("options")
    end

    it "renders a description for a setting" do
      get "/error_dashboard/settings"

      expect(response.body).to include("Catches unhandled exceptions")
      expect(response.body).to include("Stack trace depth limit")
    end

    # The config option name is an identifier, not prose. It must render exactly
    # as it is written in the initializer or it stops being greppable.
    it "renders config option names verbatim" do
      get "/error_dashboard/settings"

      text = response.body
      expect(text).to include("enable_middleware")
      expect(text).to include("max_backtrace_lines")
      expect(text).to include("detect_swallowed_exceptions")
    end

    # Ruby APIs, env vars and rake commands cited inside descriptions are
    # diagnostic references, not prose.
    it "keeps API names and env vars inside descriptions untranslated" do
      get "/error_dashboard/settings"

      text = response.body
      expect(text).to include("TracePoint(:raise)")
      expect(text).to include("at_exit")
      expect(text).to include("rails error_dashboard:cleanup_resolved")
    end
  end

  describe "value badges" do
    it "renders enabled and disabled states" do
      get "/error_dashboard/settings"

      text = response.body
      expect(text).to include("Enabled").or include("Disabled")
    end

    # The unit was an English word appended to a number. It is a plural key now.
    it "renders a numeric setting with its unit" do
      around_config(:max_backtrace_lines, 20) do
        get "/error_dashboard/settings"

        expect(response.body).to include("20 lines")
      end
    end

    it "uses the singular unit form at a count of one" do
      around_config(:max_backtrace_lines, 1) do
        get "/error_dashboard/settings"

        expect(response.body).to include("1 line<")
        expect(response.body).not_to include("1 lines")
      end
    end

    # The array/hash badges used a ? 's' : '' ternary.
    it "pluralizes array counts" do
      around_config(:ignored_exceptions, [ "FooError", "BarError" ]) do
        get "/error_dashboard/settings"

        expect(response.body).to include("2 items")
      end
    end

    it "uses the singular form for a single array item" do
      around_config(:ignored_exceptions, [ "FooError" ]) do
        get "/error_dashboard/settings"

        expect(response.body).to include("1 item<")
        expect(response.body).not_to include("1 items")
      end
    end

    it "pluralizes hash rule counts" do
      around_config(:custom_severity_rules, { "FooError" => :critical }) do
        get "/error_dashboard/settings"

        expect(response.body).to include("1 rule<")
        expect(response.body).not_to include("1 rules")
      end
    end

    # The five "absent" phrasings mean different things and stay distinct.
    it "renders the not-set badge for an unset option" do
      around_config(:app_version, nil) do
        get "/error_dashboard/settings"

        expect(response.body).to include("Not set")
      end
    end

    it "renders the retention badge with its rake command untranslated" do
      around_config(:retention_days, 90) do
        get "/error_dashboard/settings"

        expect(response.body).to include("90 days")
        expect(response.body).to include("Manual cleanup required")
        expect(response.body).to include("rails error_dashboard:cleanup_resolved DAYS=90")
      end
    end

    it "renders the keep-forever badge when retention is unset" do
      around_config(:retention_days, nil) do
        get "/error_dashboard/settings"

        expect(response.body).to include("Keep Forever")
        expect(response.body).to include("No automatic deletion")
      end
    end
  end

  describe "test notifications" do
    it "renders the section and its confirm attribute" do
      get "/error_dashboard/settings"

      button = body_doc.at_css("button[data-red-action='confirm-submit']")
      expect(button).to be_present
      expect(button["data-red-confirm-message"])
        .to eq("This will create a test error and send notifications to all configured channels. Continue?")
      expect(button.text).to include("Send Test Error")
    end

    # The error class is a constant, not prose, and renders as markup.
    it "keeps the test error class name in a code element" do
      get "/error_dashboard/settings"

      expect(response.body).to include("<code>RailsErrorDashboard::TestError</code>")
      expect(response.body).not_to include("&lt;code&gt;RailsErrorDashboard::TestError")
    end
  end

  describe "plugins" do
    it "renders the plugins section" do
      get "/error_dashboard/settings"

      expect(response.body).to include("Active Plugins")
    end
  end

  # Set a configuration value for the duration of the block and restore it.
  def around_config(attribute, value)
    config = RailsErrorDashboard.configuration
    was = config.send(attribute)
    config.send("#{attribute}=", value)
    yield
  ensure
    config.send("#{attribute}=", was)
  end
end
