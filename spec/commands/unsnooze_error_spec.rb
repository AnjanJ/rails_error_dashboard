# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::UnsnoozeError do
  describe '.call' do
    let(:error_log) { create(:error_log, snoozed_until: 2.hours.from_now) }

    it 'clears the snoozed_until timestamp' do
      result = described_class.call(error_log.id)
      expect(result.snoozed_until).to be_nil
    end

    it 'returns the updated error log' do
      result = described_class.call(error_log.id)
      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result.id).to eq(error_log.id)
    end

    it 'persists the change to the database' do
      described_class.call(error_log.id)
      expect(error_log.reload.snoozed_until).to be_nil
    end

    it 'raises ActiveRecord::RecordNotFound for invalid id' do
      expect {
        described_class.call(-1)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
