# frozen_string_literal: true

require "rails_helper"

# The contract page is the promise 1.x keeps, so it has to name everything RED
# can send. The examples are parsed, not searched, so one can't go stale.
RSpec.describe "The webhook contract page" do
  root = RailsErrorDashboard::Engine.root
  contract = RailsErrorDashboard::WebhookContract

  def field_names(body)
    body.flat_map { |key, value| value.is_a?(Hash) ? [ key, *field_names(value) ] : [ key ] }
  end

  %w[docs/WEBHOOKS.md _reference/webhooks.md].each do |page|
    describe page do
      let(:text) { File.read(root.join(page)) }
      let(:examples) { text.scan(/```json\n(.*?)```/m).flatten.map { |json| JSON.parse(json) } }

      RailsErrorDashboard::Webhooks::EVENTS.each_value do |event|
        it "shows #{event} with an example body (webhook-v1/REQ-13, REQ-14)" do
          expect(examples.map { |example| example["event"] }).to include(event)
        end

        it "gives #{event}'s example the envelope and every field (webhook-v1/REQ-13)" do
          example = examples.find { |candidate| candidate["event"] == event }

          expect(example).to include("version" => 1, "timestamp" => a_string_ending_with("Z"))
          expect(field_names(example)).to include(*field_names(contract::BODIES.fetch(event)))
        end

        it "describes every field of #{event} (webhook-v1/REQ-13)" do
          field_names(contract::BODIES.fetch(event)).each do |field|
            expect(text).to include("`#{field}`")
          end
        end
      end

      it "names every header (webhook-v1/REQ-13)" do
        expect(text).to include(*contract::HEADERS)
      end

      it "says how to verify the signature (webhook-v1/REQ-13)" do
        expect(text).to include("HMAC-SHA256", "<timestamp>.<raw body>", "WebhookSigner.valid?")
      end

      it "says when a field can be null (webhook-v1/REQ-13)" do
        expect(text).to match(/can be null/i)
      end

      it "states the 1.x promise (webhook-v1/REQ-13)" do
        expect(text).to match(/added.{0,40}never renamed or removed/m)
      end
    end
  end

  %w[docs/API_REFERENCE.md _reference/api-reference.md].each do |page|
    it "is linked from #{page} (webhook-v1/REQ-13)" do
      expect(File.read(root.join(page))).to match(/\[Webhook contract\]\([^)]*(WEBHOOKS\.md|webhooks\/)/)
    end
  end
end
