# frozen_string_literal: true

require "rails_helper"

# The three partials P2-T7 named but left behind (P2-T7c): request context,
# similar errors, and the action modals. These pin the parts that were not
# mechanical — the threshold that was written twice, the units glued onto
# numbers, and the diagnostic values that must survive untranslated.
RSpec.describe "Detail partial translations (part 3)", type: :request do
  let!(:application) { create(:application) }
  let!(:error) do
    create(:error_log, application: application, error_type: "SecurityError",
           occurrence_count: 3)
  end

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  def body_doc
    Nokogiri::HTML(response.body)
  end

  describe "request context" do
    it "renders the section title and row labels" do
      get "/error_dashboard/errors/#{error.id}"

      section = body_doc.at_css("#section-request-context")
      expect(section).to be_present
      expect(section.text).to include("Request Context")
      expect(section.text).to include("Request URL:")
      expect(section.text).to include("User Agent:")
      expect(section.text).to include("IP Address:")
    end

    # The unit was concatenated onto the number. Sub-second durations render in
    # milliseconds and anything longer in seconds; both are keys now.
    it "renders a sub-second duration in milliseconds" do
      error.update_columns(request_duration_ms: 250)

      get "/error_dashboard/errors/#{error.id}"

      expect(body_doc.at_css("#section-request-context").text).to include("250ms")
    end

    it "renders a multi-second duration in seconds" do
      error.update_columns(request_duration_ms: 5500)

      get "/error_dashboard/errors/#{error.id}"

      expect(body_doc.at_css("#section-request-context").text).to include("5.5s")
    end

    # curl and RSpec are tool names — the phrase around them is translated, the
    # names themselves are not.
    it "keeps the tool names in the copy buttons" do
      get "/error_dashboard/errors/#{error.id}"

      section = body_doc.at_css("#section-request-context")
      expect(section.text).to include("Copy as curl")
      expect(section.text).to include("Copy as RSpec")
    end

    # The HTTP verb is diagnostic output, not a UI label.
    it "renders the HTTP method verbatim" do
      error.update_columns(http_method: "PATCH")

      get "/error_dashboard/errors/#{error.id}"

      expect(body_doc.at_css("#section-request-context").text).to include("PATCH")
    end

    it "uses the shared not-available key when a value is missing" do
      error.update_columns(ip_address: nil, request_params: nil, user_agent: nil)

      get "/error_dashboard/errors/#{error.id}"

      expect(body_doc.at_css("#section-request-context").text).to include("N/A")
    end
  end

  describe "similar errors" do
    around do |example|
      was = RailsErrorDashboard.configuration.enable_similar_errors
      RailsErrorDashboard.configuration.enable_similar_errors = true
      example.run
    ensure
      RailsErrorDashboard.configuration.enable_similar_errors = was
    end

    # A shared backtrace_signature puts the candidate in front of the similarity
    # calculator, and matching backtrace/message content carries it over the 0.6
    # threshold. The factory's Faker values are too dissimilar on their own.
    let(:shared_backtrace) do
      "app/models/user.rb:10:in `save'\napp/controllers/users_controller.rb:20:in `create'"
    end

    let!(:sibling) do
      error.update_columns(message: "undefined method 'name' for nil",
                           backtrace: shared_backtrace,
                           backtrace_signature: "t7c-shared-signature")

      create(:error_log, application: application, error_type: "SecurityError",
             message: "undefined method 'name' for nil",
             backtrace: shared_backtrace,
             occurrence_count: 7, platform: "Web")
        .tap { |s| s.update_columns(backtrace_signature: "t7c-shared-signature") }
    end

    # The hint said "60%+" while the query passed 0.6. They are one value now,
    # so the prose cannot drift from the threshold actually applied.
    it "derives the hint's threshold from the value driving the query" do
      get "/error_dashboard/errors/#{error.id}"

      section = body_doc.at_css("#section-similar-errors")
      expect(section).to be_present, "expected the similar-errors section to render"

      expect(section.text).to include("60%+ similarity")
    end

    it "renders the title and the fuzzy-matching badge" do
      get "/error_dashboard/errors/#{error.id}"

      section = body_doc.at_css("#section-similar-errors")
      expect(section).to be_present, "expected the similar-errors section to render"

      expect(section.text).to include("Similar Errors")
      expect(section.text).to include("Fuzzy Matching")
    end

    # The occurrence count had a bare "x" appended. It is a plural key now, so a
    # locale that does not use that abbreviation can say something else.
    it "renders the occurrence count through a plural key" do
      get "/error_dashboard/errors/#{error.id}"

      section = body_doc.at_css("#section-similar-errors")
      expect(section).to be_present, "expected the similar-errors section to render"

      expect(section.text).to match(/\d+x/)
    end

    # Platform values are matched by string equality in the view, so translating
    # the display would decouple it from the comparison.
    it "renders the platform value verbatim" do
      get "/error_dashboard/errors/#{error.id}"

      section = body_doc.at_css("#section-similar-errors")
      expect(section).to be_present, "expected the similar-errors section to render"

      expect(section.text).to include("Web")
    end
  end

  describe "action modals" do
    it "renders each modal's title" do
      get "/error_dashboard/errors/#{error.id}"

      doc = body_doc
      expect(doc.at_css("#resolveModal").text).to include("Mark Error as Resolved")
      expect(doc.at_css("#assignModal").text).to include("Assign Error")
      expect(doc.at_css("#priorityModal").text).to include("Update Priority")
      expect(doc.at_css("#snoozeModal").text).to include("Snooze Error")
      expect(doc.at_css("#muteModal").text).to include("Mute Notifications")
    end

    it "translates placeholders, not just body text" do
      get "/error_dashboard/errors/#{error.id}"

      doc = body_doc
      expect(doc.at_css("#resolved_by_name")["placeholder"]).to eq("e.g., John Doe")
      expect(doc.at_css("#resolution_comment")["placeholder"])
        .to eq("Describe what was done to fix this error...")
    end

    it "translates the close button's aria-label" do
      get "/error_dashboard/errors/#{error.id}"

      close = body_doc.at_css("#resolveModal button.btn-close")
      expect(close["aria-label"]).to eq("Close")
    end

    # The snooze durations were English literals in an options array. The longer
    # spans are written twice in English ("24 hours (1 day)") and both halves go
    # through plural keys.
    it "renders the snooze durations through plural keys" do
      get "/error_dashboard/errors/#{error.id}"

      options = body_doc.css("#hours option").map(&:text)
      expect(options).to include("1 hour")
      expect(options).to include("4 hours")
      expect(options).to include("24 hours (1 day)")
      expect(options).to include("168 hours (1 week)")
    end

    # Singular vs plural: "1 hour" must not render as "1 hours".
    it "uses the singular form at a count of one" do
      get "/error_dashboard/errors/#{error.id}"

      options = body_doc.css("#hours option").map(&:text)
      expect(options).to include("1 hour")
      expect(options).not_to include("1 hours")
    end

    it "keeps the product names in the mute description" do
      get "/error_dashboard/errors/#{error.id}"

      text = body_doc.at_css("#muteModal").text
      expect(text).to include("Slack")
      expect(text).to include("PagerDuty")
    end
  end
end
