# frozen_string_literal: true

require "rails_helper"

# Controller flash messages and the command result strings they wrap
# (P2-T11 + P2-T12). This is the one part of Phase 2 that is not extraction:
# the batch notice conjugated English past tense by appending a "d" to a raw
# param and dodged pluralization with "error(s)". No key can express that, so
# it had to be restructured.
RSpec.describe "Flash message translations", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    # The batch endpoint is a POST and the dashboard runs
    # protect_from_forgery with: :exception; request specs carry no token.
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    ActionController::Base.allow_forgery_protection = true
  end

  def with_config(**attrs)
    config = RailsErrorDashboard.configuration
    was = attrs.keys.to_h { |k| [ k, config.send(k) ] }
    attrs.each { |k, v| config.send("#{k}=", v) }
    yield
  ensure
    was.each { |k, v| config.send("#{k}=", v) }
  end

  def batch(action, count)
    ids = Array.new(count) do |i|
      create(:error_log, application: application, message: "batch #{action} #{i} #{SecureRandom.hex(4)}").id
    end

    post "/error_dashboard/errors/batch_action", params: { action_type: action, error_ids: ids }
  end

  describe "batch actions" do
    # The heart of P2-T12. Each outcome is its own key with real plural forms,
    # because "Successfully #{action_type}d" asks every other language to
    # conjugate English.
    {
      "resolve" => "resolved",
      "mute" => "muted",
      "unmute" => "unmuted",
      "delete" => "deleted"
    }.each do |action, past|
      it "reports #{action} grammatically at one error" do
        batch(action, 1)

        expect(flash[:notice]).to eq("Successfully #{past} 1 error")
      end

      it "reports #{action} grammatically at two errors" do
        batch(action, 2)

        expect(flash[:notice]).to eq("Successfully #{past} 2 errors")
      end
    end

    it "never emits the error(s) cop-out" do
      batch("resolve", 1)

      expect(flash[:notice]).not_to include("error(s)")
    end

    # An unrecognized action is rejected by the case statement before the
    # message is built, so the lookup can never be handed a verb it cannot name.
    it "rejects an unrecognized action without raising" do
      post "/error_dashboard/errors/batch_action",
           params: { action_type: "obliterate", error_ids: [] }

      expect(response).to have_http_status(:found)
      expect(flash[:alert]).to include("Invalid action type")
    end
  end

  describe "feature-disabled notices" do
    # These were eleven near-identical sentences. They share one helper now, so
    # the wording cannot drift — but English agrees the verb and pronoun with
    # the feature name, so singular and plural features use different keys.
    it "uses singular agreement for a singular feature name" do
      with_config(enable_platform_comparison: false) do
        get "/error_dashboard/errors/platform_comparison"

        expect(flash[:alert]).to eq(
          "Platform Comparison is not enabled. " \
          "Enable it in config/initializers/rails_error_dashboard.rb"
        )
      end
    end

    it "uses plural agreement for a plural feature name" do
      with_config(enable_breadcrumbs: false) do
        get "/error_dashboard/errors/deprecations"

        expect(flash[:alert]).to eq(
          "Breadcrumbs are not enabled. " \
          "Enable them in config/initializers/rails_error_dashboard.rb"
        )
      end
    end

    # This variant names the exact option and says "Set" rather than "Enable".
    it "names the config option verbatim where the notice cites one" do
      with_config(enable_rack_attack_tracking: false) do
        get "/error_dashboard/errors/rack_attack_summary"

        expect(flash[:alert]).to eq(
          "Rack Attack tracking is not enabled. " \
          "Set enable_rack_attack_tracking = true in config/initializers/rails_error_dashboard.rb"
        )
      end
    end

    it "keeps the initializer path untranslated" do
      with_config(enable_error_correlation: false) do
        get "/error_dashboard/errors/correlation"

        expect(flash[:alert]).to include("config/initializers/rails_error_dashboard.rb")
      end
    end
  end

  describe "command result strings" do
    # A command owns half the sentence its controller shows, so the two are
    # designed together.
    it "reports a missing issue tracker through the command's own key" do
      error = create(:error_log, application: application)

      with_config(enable_issue_tracking: true, issue_tracker_token: nil) do
        post "/error_dashboard/errors/#{error.id}/create_issue"

        expect(flash[:alert]).to include("Failed to create issue:")
        expect(flash[:alert]).to include("Issue tracking is not configured")
      end
    end

    it "reports a missing issue URL when linking" do
      error = create(:error_log, application: application)

      post "/error_dashboard/errors/#{error.id}/link_issue", params: { issue_url: "" }

      expect(flash[:alert]).to include("Failed to link issue:")
      expect(flash[:alert]).to include("Issue URL is required")
    end
  end

  describe "status workflow result" do
    it "reports an invalid transition and leaves the row unchanged" do
      error = create(:error_log, application: application, status: "new")

      post "/error_dashboard/errors/#{error.id}/update_status", params: { status: "resolved" }

      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to include("new").and include("resolved")
      expect(error.reload.status).to eq("new")
      expect(error.resolved).to be_falsey
    end

    it "confirms a valid transition" do
      error = create(:error_log, application: application, status: "new")

      post "/error_dashboard/errors/#{error.id}/update_status", params: { status: "in_progress" }

      expect(flash[:alert]).to be_nil
      expect(flash[:notice]).to include("in progress")
      expect(error.reload.status).to eq("in_progress")
    end

    it "rejects an unknown status" do
      error = create(:error_log, application: application, status: "new")

      post "/error_dashboard/errors/#{error.id}/update_status", params: { status: "banana" }

      expect(flash[:alert]).to eq(I18n.t("red.flash.status.unknown"))
      expect(error.reload.status).to eq("new")
    end

    it "rejects a status that arrives as a nested parameter" do
      error = create(:error_log, application: application, status: "new")

      post "/error_dashboard/errors/#{error.id}/update_status", params: { status: { "x" => "resolved" } }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("red.flash.status.unknown"))
      expect(error.reload.status).to eq("new")
    end
  end

  describe "workflow input validation" do
    let(:error) { create(:error_log, application: application, status: "new", priority_level: 2) }

    [ "-100000", "0", "721", "abc", "", "1.5" ].each do |hours|
      it "refuses to snooze for #{hours.inspect} hours" do
        post "/error_dashboard/errors/#{error.id}/snooze", params: { hours: hours }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq(I18n.t("red.flash.snooze.invalid_hours", max: 720))
        expect(error.reload.snoozed_until).to be_nil
      end
    end

    it "refuses snooze hours sent as a nested parameter" do
      post "/error_dashboard/errors/#{error.id}/snooze", params: { hours: { "a" => "24" } }

      expect(flash[:alert]).to eq(I18n.t("red.flash.snooze.invalid_hours", max: 720))
      expect(error.reload.snoozed_until).to be_nil
    end

    it "snoozes for a valid number of hours" do
      post "/error_dashboard/errors/#{error.id}/snooze", params: { hours: "24" }

      expect(flash[:alert]).to be_nil
      expect(error.reload.snoozed_until).to be_within(1.minute).of(24.hours.from_now)
    end

    [ "99", "-1", "x", "", "1.5" ].each do |level|
      it "refuses priority #{level.inspect} and keeps the existing priority" do
        post "/error_dashboard/errors/#{error.id}/update_priority", params: { priority_level: level }

        expect(flash[:alert]).to eq(I18n.t("red.flash.priority.invalid"))
        expect(error.reload.priority_level).to eq(2)
      end
    end

    it "refuses a priority sent as a nested parameter" do
      post "/error_dashboard/errors/#{error.id}/update_priority", params: { priority_level: { "foo" => "bar" } }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("red.flash.priority.invalid"))
      expect(error.reload.priority_level).to eq(2)
    end

    it "accepts a valid priority" do
      post "/error_dashboard/errors/#{error.id}/update_priority", params: { priority_level: "3" }

      expect(flash[:alert]).to be_nil
      expect(error.reload.priority_level).to eq(3)
    end

    [ "", "   ", nil ].each do |name|
      it "refuses to assign to #{name.inspect}" do
        post "/error_dashboard/errors/#{error.id}/assign", params: { assigned_to: name }

        expect(flash[:alert]).to eq(I18n.t("red.flash.assign.blank"))
        expect(error.reload.assigned_to).to be_nil
        expect(error.status).to eq("new")
      end
    end

    it "refuses an assignee sent as a nested parameter" do
      post "/error_dashboard/errors/#{error.id}/assign", params: { assigned_to: { "a" => "b" } }

      expect(flash[:alert]).to eq(I18n.t("red.flash.assign.blank"))
      expect(error.reload.assigned_to).to be_nil
    end

    it "assigns to a trimmed name" do
      post "/error_dashboard/errors/#{error.id}/assign", params: { assigned_to: "  gandalf " }

      expect(flash[:alert]).to be_nil
      expect(error.reload.assigned_to).to eq("gandalf")
      expect(error.status).to eq("in_progress")
    end
  end

  describe "AI help JSON errors" do
    let(:error) { create(:error_log, application: application) }

    # The message is rendered in the help panel, so it is translated. The HTTP
    # status carrying it is machine-readable and untouched.
    it "translates the not-configured message and keeps the status" do
      post "/error_dashboard/errors/#{error.id}/ai_help", params: { question: "why?" }

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("AI Help is not configured")
    end

    # The limit was written twice — once in the check, once in the message.
    it "reports the question limit from the constant that enforces it" do
      limit = RailsErrorDashboard::ErrorsController::AI_HELP_QUESTION_LIMIT

      with_config(llm_api_key: "test-key", llm_provider: :openai) do
        post "/error_dashboard/errors/#{error.id}/ai_help",
             params: { question: "x" * (limit + 1) }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"])
          .to eq("Question is too long. Keep it under 4,000 characters.")
      end
    end
  end
end
