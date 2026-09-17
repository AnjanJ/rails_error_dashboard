# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::AssignError do
  describe '.call' do
    let(:error_log) { create(:error_log) }

    it 'assigns the error to the given user' do
      result = described_class.call(error_log.id, assigned_to: 'gandalf')[:error]
      expect(result.assigned_to).to eq('gandalf')
    end

    it 'sets assigned_at timestamp' do
      freeze_time do
        result = described_class.call(error_log.id, assigned_to: 'gandalf')[:error]
        expect(result.assigned_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'auto-transitions status to in_progress' do
      result = described_class.call(error_log.id, assigned_to: 'gandalf')[:error]
      expect(result.status).to eq('in_progress')
    end

    it 'returns the updated error log' do
      result = described_class.call(error_log.id, assigned_to: 'gandalf')[:error]
      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result).to be_persisted
      expect(result.id).to eq(error_log.id)
    end

    it 'persists the changes to the database' do
      described_class.call(error_log.id, assigned_to: 'gandalf')
      expect(error_log.reload.assigned_to).to eq('gandalf')
    end

    it 'reports success with the record' do
      result = described_class.call(error_log.id, assigned_to: 'gandalf')
      expect(result[:success]).to be true
      expect(result[:error]).to eq(error_log)
    end

    it 'trims the name' do
      described_class.call(error_log.id, assigned_to: "  gandalf \n")
      expect(error_log.reload.assigned_to).to eq('gandalf')
    end

    it 'caps the name at 255 characters' do
      described_class.call(error_log.id, assigned_to: 'x' * 500)
      expect(error_log.reload.assigned_to.length).to eq(255)
    end

    [ '', '   ', "\t\n", nil, { 'a' => 'b' }, [ 'gandalf' ], 42 ].each do |name|
      it "fails with :blank_assignee for #{name.inspect} and changes nothing" do
        result = described_class.call(error_log.id, assigned_to: name)

        expect(result).to include(success: false, reason: :blank_assignee)
        error_log.reload
        expect(error_log.assigned_to).to be_nil
        expect(error_log.assigned_at).to be_nil
        expect(error_log.status).to eq('new')
      end
    end

    it 'raises ActiveRecord::RecordNotFound for invalid id' do
      expect {
        described_class.call(-1, assigned_to: 'gandalf')
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
