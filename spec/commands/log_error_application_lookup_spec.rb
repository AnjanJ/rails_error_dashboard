# frozen_string_literal: true

require "rails_helper"

# A connection timeout in the application lookup ends the capture there
# (hardening-1-0-rc2/REQ-21). The fallback, Application.first, asks the same
# starved pool for a connection, so it waited the whole checkout_timeout a
# second time on the request's thread.
RSpec.describe RailsErrorDashboard::Commands::LogError, "application lookup" do
  let(:application_model) { RailsErrorDashboard::Application }

  def capture
    error = ArgumentError.new("lookup")
    error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:3:in 'load'" ])
    described_class.call(error, {})
  end

  before { RailsErrorDashboard.configuration.async_logging = false }

  it "doesn't take the fallback after a connection timeout, and returns nil without raising (hardening-1-0-rc2/REQ-21)" do
    allow(application_model).to receive(:find_or_create_by_name)
      .and_raise(ActiveRecord::ConnectionTimeoutError, "could not obtain a connection from the pool")
    allow(application_model).to receive(:first).and_call_original

    result = nil
    expect { result = capture }.not_to raise_error

    expect(result).to be_nil
    expect(application_model).not_to have_received(:first)
    expect(RailsErrorDashboard::ErrorLog.count).to eq(0)
  end

  it "still takes the fallback after any other error (hardening-1-0-rc2/REQ-21)" do
    fallback = application_model.create!(name: "Fallback App")
    allow(application_model).to receive(:find_or_create_by_name).and_raise(ActiveRecord::StatementInvalid, "boom")
    allow(application_model).to receive(:first).and_call_original

    result = capture

    expect(application_model).to have_received(:first)
    expect(result).to be_a(RailsErrorDashboard::ErrorLog)
    expect(result.application_id).to eq(fallback.id)
  end
end
