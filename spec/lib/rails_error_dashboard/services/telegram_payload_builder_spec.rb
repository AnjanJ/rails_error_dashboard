# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::TelegramPayloadBuilder do
  let!(:application) { create(:application, name: "Shop") }
  let!(:error_log) do
    create(:error_log,
      application: application,
      error_type: "Net::OpenTimeout",
      message: "connect to <db> failed & retried",
      controller_name: "posts",
      action_name: "create",
      platform: "API",
      occurrence_count: 5,
      backtrace: "app/models/post.rb:10:in `save'\napp/controllers/posts_controller.rb:20")
  end

  after { RailsErrorDashboard.reset_configuration! }

  describe ".call" do
    subject(:payload) { described_class.call(error_log) }

    let(:text) { payload[:text] }

    it "asks for HTML parse mode without link previews, and leaves chat_id to the delivery" do
      expect(payload).to include(parse_mode: "HTML", disable_web_page_preview: true)
      expect(payload).not_to have_key(:chat_id)
    end

    it "opens with the heading and the error type in bold" do
      expect(text).to start_with("<b>🚨 Error Alert</b>\n<b>Net::OpenTimeout</b>\n")
    end

    it "escapes HTML in the message so a < in it cannot break the parser" do
      expect(text).to include("<code>connect to &lt;db&gt; failed &amp; retried</code>")
      expect(text).not_to include("<db>")
    end

    it "renders each label bold with the value beside it" do
      expect(text).to include("<b>Application:</b> Shop")
      expect(text).to include("<b>Platform:</b> API")
      expect(text).to include("<b>Occurrences:</b> 5")
      expect(text).to include("<b>Controller:</b> posts")
      expect(text).to include("<b>Action:</b> create")
      expect(text).to match(/<b>First Seen:<\/b> \S/)
    end

    it "puts the first backtrace line, and only that line, in a code span" do
      expect(text).to include("<b>Location:</b> <code>app/models/post.rb:10:in `save&#39;</code>")
      expect(text).not_to include("posts_controller.rb")
    end

    it "ends with a link to the error in the dashboard" do
      RailsErrorDashboard.configuration.dashboard_base_url = "https://errors.example.com"

      expect(text).to end_with(
        %(<a href="https://errors.example.com/error_dashboard/errors/#{error_log.id}">View in Error Dashboard</a>)
      )
    end

    it "truncates a long message to 500 characters" do
      error_log.update!(message: "x" * 600)

      expect(text).to include("<code>#{'x' * 500}...</code>")
    end

    it "uses only tags Telegram accepts" do
      tags = text.scan(/<\/?([a-z]+)[\s>]/).flatten.uniq
      expect(tags).to all(be_in(%w[b code a]))
    end

    context "with an environment" do
      before { error_log.update!(environment: "production") }

      it "adds an Environment line" do
        expect(text).to include("<b>Environment:</b> production")
      end
    end

    context "without controller, action or backtrace" do
      before { error_log.update!(controller_name: nil, action_name: nil, backtrace: nil) }

      it "falls back to N/A" do
        expect(text).to include("<b>Controller:</b> N/A", "<b>Action:</b> N/A", "<b>Location:</b> <code>N/A</code>")
      end
    end

    context "in another locale" do
      subject(:payload) { described_class.call(error_log, locale: "de") }

      it "translates the heading and labels but not the error content" do
        expect(text).to include("Net::OpenTimeout", "connect to &lt;db&gt;")
        expect(text).not_to include("Error Alert")
        expect(text).to include(RailsErrorDashboard::I18nStore.translate("red.notifications.error_alert.heading", locale: "de"))
      end
    end
  end

  describe ".html_payload" do
    it "degrades to plain text, with tags stripped and entities decoded, when the text would not fit" do
      long = "<b>#{'a' * 4000}</b>\n<code>&lt;x&gt; #{'b' * 200}</code>"

      payload = described_class.html_payload(long)

      expect(payload).not_to have_key(:parse_mode)
      expect(payload[:text].length).to be <= described_class::MAX_TEXT_LENGTH
      expect(payload[:text]).to start_with("a" * 4000)
      expect(payload[:text]).to include("<x>")
      expect(payload[:text]).not_to include("<b>", "<code>")
    end
  end
end
