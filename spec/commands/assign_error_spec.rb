# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::AssignError do
  describe '.call' do
    let(:error_log) { create(:error_log) }

    it 'assigns the error to the given user' do
      result = described_class.call(error_log.id, assigned_to: 'gandalf')
      expect(result.assigned_to).to eq('gandalf')
    end

    it 'sets assigned_at timestamp' do
      freeze_time do
        result = described_class.call(error_log.id, assigned_to: 'gandalf')
        expect(result.assigned_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'auto-transitions status to in_progress' do
      result = described_class.call(error_log.id, assigned_to: 'gandalf')
      expect(result.status).to eq('in_progress')
    end

    it 'returns the updated error log' do
      result = described_class.call(error_log.id, assigned_to: 'gandalf')
      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result).to be_persisted
      expect(result.id).to eq(error_log.id)
    end

    it 'persists the changes to the database' do
      described_class.call(error_log.id, assigned_to: 'gandalf')
      expect(error_log.reload.assigned_to).to eq('gandalf')
    end

    it 'raises ActiveRecord::RecordNotFound for invalid id' do
      expect {
        described_class.call(-1, assigned_to: 'gandalf')
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
