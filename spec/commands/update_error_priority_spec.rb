# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::UpdateErrorPriority do
  describe '.call' do
    let(:error_log) { create(:error_log, priority_level: 0) }

    it 'updates the priority level' do
      result = described_class.call(error_log.id, priority_level: 3)[:error]
      expect(result.priority_level).to eq(3)
    end

    it 'persists the change to the database' do
      described_class.call(error_log.id, priority_level: 2)
      expect(error_log.reload.priority_level).to eq(2)
    end

    it 'returns the updated error log' do
      result = described_class.call(error_log.id, priority_level: 1)[:error]
      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result.id).to eq(error_log.id)
    end

    it 'sets priority to critical (3)' do
      result = described_class.call(error_log.id, priority_level: 3)[:error]
      expect(result.reload.priority_level).to eq(3)
    end

    it 'sets priority to low (0)' do
      error_log.update!(priority_level: 3)
      result = described_class.call(error_log.id, priority_level: 0)[:error]
      expect(result.reload.priority_level).to eq(0)
    end

    it 'reports success with the record' do
      result = described_class.call(error_log.id, priority_level: 2)
      expect(result[:success]).to be true
      expect(result[:error]).to eq(error_log)
    end

    it 'accepts the level as a numeric string' do
      expect(described_class.call(error_log.id, priority_level: '3')[:success]).to be true
      expect(error_log.reload.priority_level).to eq(3)
    end

    [ 99, -1, 4, 'x', '', 'P0', 1.5, nil, { 'foo' => 'bar' }, [ 1 ] ].each do |level|
      it "fails with :invalid_priority for #{level.inspect} and keeps the existing priority" do
        error_log.update!(priority_level: 2)

        result = described_class.call(error_log.id, priority_level: level)

        expect(result).to include(success: false, reason: :invalid_priority)
        expect(error_log.reload.priority_level).to eq(2)
      end
    end

    it 'raises ActiveRecord::RecordNotFound for invalid id' do
      expect {
        described_class.call(-1, priority_level: 1)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
