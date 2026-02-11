# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::UpdateErrorPriority do
  describe '.call' do
    let(:error_log) { create(:error_log, priority_level: 0) }

    it 'updates the priority level' do
      result = described_class.call(error_log.id, priority_level: 3)
      expect(result.priority_level).to eq(3)
    end

    it 'persists the change to the database' do
      described_class.call(error_log.id, priority_level: 2)
      expect(error_log.reload.priority_level).to eq(2)
    end

    it 'returns the updated error log' do
      result = described_class.call(error_log.id, priority_level: 1)
      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result.id).to eq(error_log.id)
    end

    it 'sets priority to critical (3)' do
      result = described_class.call(error_log.id, priority_level: 3)
      expect(result.reload.priority_level).to eq(3)
    end

    it 'sets priority to low (0)' do
      error_log.update!(priority_level: 3)
      result = described_class.call(error_log.id, priority_level: 0)
      expect(result.reload.priority_level).to eq(0)
    end

    it 'raises ActiveRecord::RecordNotFound for invalid id' do
      expect {
        described_class.call(-1, priority_level: 1)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
