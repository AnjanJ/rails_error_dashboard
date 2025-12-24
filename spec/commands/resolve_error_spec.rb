# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::ResolveError do
  describe '.call' do
    let(:error_log) { create(:error_log) }
    let(:params) do
      {
        resolved_by_name: 'John Doe',
        resolution_comment: 'Fixed in PR #123',
        resolution_reference: 'PR-123'
      }
    end

    it 'marks the error as resolved' do
      described_class.call(error_log.id, params)
      expect(error_log.reload.resolved).to be true
    end

    it 'sets the resolver name' do
      described_class.call(error_log.id, params)
      expect(error_log.reload.resolved_by_name).to eq('John Doe')
    end

    it 'sets the resolution comment' do
      described_class.call(error_log.id, params)
      expect(error_log.reload.resolution_comment).to eq('Fixed in PR #123')
    end

    it 'sets the resolution reference' do
      described_class.call(error_log.id, params)
      expect(error_log.reload.resolution_reference).to eq('PR-123')
    end

    it 'sets resolved_at timestamp' do
      freeze_time do
        described_class.call(error_log.id, params)
        expect(error_log.reload.resolved_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'returns the updated error log' do
      result = described_class.call(error_log.id, params)
      expect(result.id).to eq(error_log.id)
      expect(result).to be_persisted
    end

    context 'when error is already resolved' do
      let(:error_log) { create(:error_log, :resolved) }

      it 'updates the resolution details' do
        new_comment = 'Updated resolution'
        described_class.call(error_log.id, params.merge(resolution_comment: new_comment))
        expect(error_log.reload.resolution_comment).to eq(new_comment)
      end
    end

    context 'with minimal params' do
      let(:params) { { resolved_by_name: 'Jane Doe' } }

      it 'marks error as resolved without optional fields' do
        described_class.call(error_log.id, params)
        expect(error_log.reload.resolved).to be true
        expect(error_log.resolved_by_name).to eq('Jane Doe')
        expect(error_log.resolution_comment).to be_nil
        expect(error_log.resolution_reference).to be_nil
      end
    end
  end
end
