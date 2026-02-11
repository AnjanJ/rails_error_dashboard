# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::UnassignError do
  describe '.call' do
    let(:error_log) { create(:error_log, assigned_to: 'gandalf', assigned_at: 1.hour.ago) }

    it 'clears the assigned_to field' do
      result = described_class.call(error_log.id)
      expect(result.assigned_to).to be_nil
    end

    it 'clears the assigned_at timestamp' do
      result = described_class.call(error_log.id)
      expect(result.assigned_at).to be_nil
    end

    it 'returns the updated error log' do
      result = described_class.call(error_log.id)
      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result.id).to eq(error_log.id)
    end

    it 'persists the changes to the database' do
      described_class.call(error_log.id)
      error_log.reload
      expect(error_log.assigned_to).to be_nil
      expect(error_log.assigned_at).to be_nil
    end

    it 'raises ActiveRecord::RecordNotFound for invalid id' do
      expect {
        described_class.call(-1)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
