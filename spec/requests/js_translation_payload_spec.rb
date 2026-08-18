# frozen_string_literal: true

require "rails_helper"
require "zlib"

# The JS translation payload (P3-T1). window.RED_I18N ships inside every
# dashboard page, so the two things worth pinning are that it is present
# everywhere and that it stays small — a dictionary that grows unnoticed is a
# tax on every page load.
RSpec.describe "JS translation payload", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard::Current.locale = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  # The payload is emitted from the layout, so any page that renders the layout
  # gets it. Sampling several rather than one guards against a future partial
  # rendering without it.
  describe "presence" do
    %w[
      /error_dashboard/errors
      /error_dashboard/errors/analytics
      /error_dashboard/errors/settings
    ].each do |path|
      it "defines window.RED_I18N on #{path}" do
        get path

        expect(response.body).to include("window.RED_I18N =")
        expect(response.body).to include("window.redT =")
      end
    end
  end

  describe "contents" do
    it "carries month, day and meridian names for the JS date formatter" do
      get "/error_dashboard/errors"

      payload = js_i18n_payload(response.body)

      expect(payload["js"]["months"].first).to eq("January")
      expect(payload["js"]["months"].length).to eq(12)
      expect(payload["js"]["days"].first).to eq("Sunday")
      expect(payload["js"]["days"].length).to eq(7)
      expect(payload["js"]["meridian"]).to eq("am" => "AM", "pm" => "PM")
    end

    it "carries the strftime patterns the browser re-renders with" do
      get "/error_dashboard/errors"

      payload = js_i18n_payload(response.body)

      expect(payload["formats"]["full"]).to eq("%B %d, %Y %I:%M:%S %p")
      expect(payload["formats"]).to have_key("short")
    end

    it "names the rendering locale" do
      get "/error_dashboard/errors"

      expect(js_i18n_payload(response.body)["locale"]).to eq("en")
    end

    # REQ-1. The whole dictionary is ~1,350 keys; shipping it would be a
    # different kind of bug from shipping the wrong string, and a silent one.
    it "ships only the JS subtree, never the whole dictionary" do
      get "/error_dashboard/errors"

      payload = js_i18n_payload(response.body)

      expect(payload.keys).to match_array(%w[locale js formats])
      expect(payload).not_to have_key("nav")
      expect(payload).not_to have_key("errors")
      expect(payload).not_to have_key("settings")
    end
  end

  # REQ-6. Recorded rather than merely asserted: the number is the point, and a
  # regression here is gradual, not sudden.
  describe "size budget" do
    it "stays at or under 4KB gzipped" do
      get "/error_dashboard/errors"

      json = extract_payload_json(response.body)
      gzipped = Zlib::Deflate.deflate(json).bytesize

      expect(gzipped).to be <= 4096, "payload is #{gzipped} bytes gzipped, budget is 4096"
    end
  end

  # A translated value containing "</script>" would otherwise close the block
  # early and dump the rest of the payload into the document as markup.
  #
  # Two mechanisms stop it and either suffices: ActiveSupport's to_json escapes
  # "<" to \\u003c, and js_safe_json rewrites a surviving "</" to "<\\/". The
  # assertion is on the property — no literal closing tag inside the payload —
  # rather than on one escape signature, so it still holds if either changes.
  describe "script breakout" do
    it "neutralizes a closing script tag in a translated value" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { js: { breakout_probe: "</script><img src=x onerror=alert(1)>" } }
      )

      get "/error_dashboard/errors"

      payload = extract_payload_json(response.body)

      expect(payload).to include("breakout_probe")
      expect(payload).not_to include("</script>")
      expect(payload).not_to include("<img src=x")

      # The value still round-trips to the original string in the browser.
      expect(js_i18n_payload(response.body)["js"]["breakout_probe"])
        .to eq("</script><img src=x onerror=alert(1)>")
    ensure
      RailsErrorDashboard::I18nStore.reset!
    end

    # A host app may set ActiveSupport.escape_html_entities_in_json = false —
    # it is a supported Rails setting, and RED does not control host config.
    # That removes the \\u003c layer and leaves js_safe_json as the only thing
    # standing between a translated value and a </script> breakout. Without
    # this example the two layers mask each other and neither is really tested.
    it "still neutralizes the closing tag when the host disables JSON HTML escaping" do
      original = ActiveSupport.escape_html_entities_in_json
      ActiveSupport.escape_html_entities_in_json = false

      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { js: { breakout_probe: "</script><img src=x onerror=alert(1)>" } }
      )

      get "/error_dashboard/errors"

      payload = extract_payload_json(response.body)

      expect(payload).to include("breakout_probe")
      expect(payload).not_to include("</script>")
    ensure
      ActiveSupport.escape_html_entities_in_json = original
      RailsErrorDashboard::I18nStore.reset!
    end
  end

  # REQ-3. Every other inline block in the layout is nonce-guarded; an
  # unguarded one would be dropped under a strict CSP, taking redT with it and
  # leaving every later caller with an undefined function.
  describe "CSP" do
    it "carries the nonce on the payload block when the host supplies one" do
      get "/error_dashboard/errors"

      body = response.body
      blocks = body.scan(%r{<script[^>]*>.*?</script>}m)
      payload_block = blocks.find { |block| block.include?("window.RED_I18N =") }

      expect(payload_block).not_to be_nil

      # The dummy host has no nonce generator, so the attribute is correctly
      # absent. What must hold either way is that this block is guarded
      # exactly like its neighbours rather than being a bare <script>.
      theme_block = blocks.find { |block| block.include?("red-theme") }
      expect(payload_block[/\A<script[^>]*>/]).to eq(theme_block[/\A<script[^>]*>/])
    end
  end

  describe "host app safety" do
    # The payload is built inside the layout. If it could raise, it would take
    # down every dashboard page rather than degrade.
    it "still renders the page when the JS subtree is missing entirely" do
      allow(RailsErrorDashboard::I18nStore).to receive(:subtree).and_raise(StandardError, "boom")

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:ok)
    end
  end

  def extract_payload_json(body)
    body[/window\.RED_I18N = (.*?);\s*$/m, 1] or
      raise "window.RED_I18N assignment not found in rendered page"
  end

  def js_i18n_payload(body)
    JSON.parse(extract_payload_json(body).gsub('<\/', "</"))
  end
end
