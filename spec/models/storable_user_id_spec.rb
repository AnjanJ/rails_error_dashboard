# frozen_string_literal: true

require "rails_helper"

# A user_id the column can't hold is stored as nil, and the capture is kept
# (hardening-1-0-rc2/REQ-15). Writing it raised ActiveModel::RangeError, and the
# whole capture was lost. The check reads each model's own user_id column, so
# it covers the error log and the occurrence alike.
RSpec.describe "storable user_id" do
  let(:error_log) { RailsErrorDashboard::ErrorLog }
  let(:occurrence) { RailsErrorDashboard::ErrorOccurrence }

  def with_user_id_type(model, type)
    allow(model).to receive(:type_for_attribute).and_call_original
    allow(model).to receive(:type_for_attribute).with("user_id").and_return(type)
  end

  {
    "error log" => RailsErrorDashboard::ErrorLog,
    "occurrence" => RailsErrorDashboard::ErrorOccurrence
  }.each do |label, model|
    context "the #{label}'s column" do
      it "stores 2**40 as nil on a 4-byte column (hardening-1-0-rc2/REQ-15)" do
        with_user_id_type(model, ActiveModel::Type::Integer.new(limit: 4))

        expect(error_log.storable_user_id(2**40, model: model)).to be_nil
        expect(error_log.storable_user_id((2**40).to_s, model: model)).to be_nil
      end

      it "keeps 2**31 - 1 on a 4-byte column (hardening-1-0-rc2/REQ-15)" do
        with_user_id_type(model, ActiveModel::Type::Integer.new(limit: 4))

        expect(error_log.storable_user_id(2**31 - 1, model: model)).to eq(2**31 - 1)
        expect(error_log.storable_user_id(-(2**31), model: model)).to eq(-(2**31))
      end

      it "keeps 2**40 on an 8-byte column (hardening-1-0-rc2/REQ-15)" do
        with_user_id_type(model, ActiveModel::Type::Integer.new(limit: 8))

        expect(error_log.storable_user_id(2**40, model: model)).to eq(2**40)
      end

      it "passes strings through on a non-integer (uuid) column (hardening-1-0-rc2/REQ-15)" do
        with_user_id_type(model, ActiveModel::Type::String.new)
        uuid = "3f2a9c1e-1b2c-4d5e-8f90-123456789abc"

        expect(error_log.storable_user_id(uuid, model: model)).to eq(uuid)
      end
    end
  end

  it "still turns a non-integer string into nil on an integer column" do
    expect(error_log.storable_user_id("3f2a9c1e-1b2c-4d5e-8f90-123456789abc")).to be_nil
  end

  # The two columns can differ (a host widened one), so the occurrence's id is
  # checked against the occurrence's column, not only the error log's.
  it "checks the occurrence's user_id against the occurrence's own column (hardening-1-0-rc2/REQ-15)" do
    RailsErrorDashboard.configuration.async_logging = false
    allow(error_log).to receive(:storable_user_id).and_call_original
    error = ArgumentError.new("user id check")
    error.set_backtrace([ "#{Rails.root}/app/models/user.rb:3:in 'load'" ])

    RailsErrorDashboard::Commands::LogError.call(error, { user_id: 42 })

    expect(error_log).to have_received(:storable_user_id).with(42, model: occurrence)
  end

  # End to end, on whatever column this database has: 2**70 is out of range
  # for a 4-byte and an 8-byte integer alike.
  it "stores a capture whose user_id is out of range, with a nil user_id on the error and the occurrence (hardening-1-0-rc2/REQ-15)" do
    RailsErrorDashboard.configuration.async_logging = false
    error = ArgumentError.new("user id overflow")
    error.set_backtrace([ "#{Rails.root}/app/models/user.rb:3:in 'load'" ])

    result = RailsErrorDashboard::Commands::LogError.call(error, { user_id: 2**70 })

    expect(result).to be_a(RailsErrorDashboard::ErrorLog)
    expect(result.reload.user_id).to be_nil
    expect(occurrence.where(error_log_id: result.id).pluck(:user_id)).to eq([ nil ])
  end
end
