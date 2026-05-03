# frozen_string_literal: true

require "rails_helper"

# Regression test for the production CSP bug discovered on zerocourse.dev
# (May 2026): the host app enforces a strict Content Security Policy with a
# nonce (`script-src 'self' 'nonce-...'`), so every dashboard page that used
# inline `onclick="..."` event handlers or bare `<script>` tags failed to run.
# The error rows could not be clicked and the console was filled with
# "Executing inline event handler violates ... Content Security Policy"
# warnings.
#
# These specs lock in two invariants that protect the dashboard against any
# future host CSP — even hosts that haven't enabled CSP yet should not regress
# to inline handlers, because users who enable CSP later would silently break.
RSpec.describe "Dashboard CSP compatibility", type: :request do
  let!(:application) { create(:application) }
  let!(:error) { create(:error_log, application: application) }

  let(:auth_headers) do
    creds = ::Base64.strict_encode64("gandalf:youshallnotpass")
    { "HTTP_AUTHORIZATION" => "Basic #{creds}" }
  end

  # Strip <script>...</script> blocks so JS-internal mentions of "onclick"
  # in comments don't trip the assertion. We only care about HTML attributes.
  def html_outside_scripts(body)
    body.gsub(%r{<script[^>]*>.*?</script>}m, "")
  end

  shared_examples "no inline event handlers" do |path|
    it "renders #{path} with no inline event handler attributes" do
      get path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      handlers = html_outside_scripts(response.body).scan(
        /\son(?:click|mouseenter|mouseleave|change|submit|input|keydown|keyup|focus|blur|load|error)\s*=/i
      )
      expect(handlers).to be_empty,
        "Inline event handlers leak (would break under host CSP). Found: #{handlers.first(3).inspect}"
    end
  end

  include_examples "no inline event handlers", "/error_dashboard"
  include_examples "no inline event handlers", "/error_dashboard/errors"
  include_examples "no inline event handlers", "/error_dashboard/settings"

  describe "ApplicationHelper#red_csp_nonce" do
    it "returns nil when the host has no CSP nonce generator" do
      helper_klass = Class.new do
        include RailsErrorDashboard::ApplicationHelper
      end
      expect(helper_klass.new.red_csp_nonce).to be_nil
    end

    it "returns the host's CSP nonce when one is available" do
      helper_klass = Class.new do
        include RailsErrorDashboard::ApplicationHelper
        def content_security_policy_nonce
          "host-supplied-nonce-xyz"
        end
      end
      expect(helper_klass.new.red_csp_nonce).to eq("host-supplied-nonce-xyz")
    end

    it "returns nil if the host's nonce helper raises" do
      helper_klass = Class.new do
        include RailsErrorDashboard::ApplicationHelper
        def content_security_policy_nonce
          raise "boom"
        end
      end
      expect(helper_klass.new.red_csp_nonce).to be_nil
    end
  end

  describe "inline <script> tags carry the host nonce when available" do
    # The render path uses `red_csp_nonce` which calls
    # `content_security_policy_nonce` if it's defined on the controller. So
    # rather than fight Rails' CSP middleware here, we just verify that the
    # rendered scripts use ERB conditional that includes the nonce when
    # red_csp_nonce returns truthy.
    it "every inline <script> open-tag in our views is templated with the nonce conditional" do
      bad_files = []
      view_files = Dir[Rails.root.join("..", "..", "app/views/**/*.erb").to_s]
      view_files.each do |f|
        contents = File.read(f)
        # Find <script> tags that aren't src= AND don't include the nonce ERB.
        scripts = contents.scan(/<script(?![^>]*\bsrc=)([^>]*)>/i)
        scripts.each do |attrs,|
          next if attrs.include?("red_csp_nonce")
          bad_files << "#{f}: <script#{attrs}>"
        end
      end
      expect(bad_files).to be_empty,
        "Found inline <script> tags missing nonce template:\n#{bad_files.join("\n")}"
    end
  end
end
