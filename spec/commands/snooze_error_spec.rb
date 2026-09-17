# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::SnoozeError do
  describe '.call' do
    let(:error_log) { create(:error_log) }

    it 'sets the snoozed_until timestamp' do
      freeze_time do
        result = described_class.call(error_log.id, hours: 2)[:error]
        expect(result.snoozed_until).to be_within(1.second).of(2.hours.from_now)
      end
    end

    it 'creates a comment when reason is provided' do
      expect {
        described_class.call(error_log.id, hours: 1, reason: 'waiting for deploy')
      }.to change(RailsErrorDashboard::ErrorComment, :count).by(1)
    end

    it 'sets comment body with snooze details' do
      described_class.call(error_log.id, hours: 3, reason: 'known issue')
      comment = error_log.comments.last
      expect(comment.body).to include('Snoozed for 3 hours')
      expect(comment.body).to include('known issue')
    end

    it 'sets comment author to assigned user or System' do
      described_class.call(error_log.id, hours: 1, reason: 'test')
      comment = error_log.comments.last
      expect(comment.author_name).to eq('System')
    end

    it 'uses assigned user as comment author when assigned' do
      error_log.update!(assigned_to: 'gandalf')
      described_class.call(error_log.id, hours: 1, reason: 'test')
      comment = error_log.comments.last
      expect(comment.author_name).to eq('gandalf')
    end

    it 'does not create a comment when no reason is provided' do
      expect {
        described_class.call(error_log.id, hours: 1)
      }.not_to change(RailsErrorDashboard::ErrorComment, :count)
    end

    it 'returns the updated error log' do
      result = described_class.call(error_log.id, hours: 2)[:error]
      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result.id).to eq(error_log.id)
    end

    it 'persists the snoozed_until to the database' do
      described_class.call(error_log.id, hours: 4)
      expect(error_log.reload.snoozed_until).to be_present
    end

    it 'reports success with the record' do
      result = described_class.call(error_log.id, hours: 2)
      expect(result[:success]).to be true
      expect(result[:error]).to eq(error_log)
    end

    it 'accepts the hours as a numeric string' do
      expect(described_class.call(error_log.id, hours: '24')[:success]).to be true
      expect(error_log.reload.snoozed_until).to be_within(1.minute).of(24.hours.from_now)
    end

    it 'accepts the maximum' do
      expect(described_class.call(error_log.id, hours: described_class::MAX_SNOOZE_HOURS)[:success]).to be true
    end

    [ -100_000, -1, 0, 721, 10**12, 1.5, 'abc', '', '1.5', nil, { 'a' => 1 }, [ 24 ] ].each do |hours|
      it "fails with :invalid_hours for #{hours.inspect} and writes nothing" do
        result = nil
        expect {
          result = described_class.call(error_log.id, hours: hours, reason: 'should not be saved')
        }.not_to change(RailsErrorDashboard::ErrorComment, :count)

        expect(result).to include(success: false, reason: :invalid_hours)
        expect(result[:error]).to eq(error_log)
        expect(error_log.reload.snoozed_until).to be_nil
      end
    end

    it 'raises ActiveRecord::RecordNotFound for invalid id' do
      expect {
        described_class.call(-1, hours: 1)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
