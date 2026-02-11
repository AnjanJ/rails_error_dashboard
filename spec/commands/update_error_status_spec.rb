# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::UpdateErrorStatus do
  describe '.call' do
    let(:error_log) { create(:error_log, status: 'new') }

    context 'with valid transition' do
      it 'updates the status' do
        result = described_class.call(error_log.id, status: 'in_progress')
        expect(result[:error].status).to eq('in_progress')
      end

      it 'returns success true' do
        result = described_class.call(error_log.id, status: 'in_progress')
        expect(result[:success]).to be true
      end

      it 'persists the status to the database' do
        described_class.call(error_log.id, status: 'in_progress')
        expect(error_log.reload.status).to eq('in_progress')
      end
    end

    context 'when transitioning to resolved' do
      let(:error_log) { create(:error_log, status: 'in_progress') }

      it 'auto-sets resolved to true' do
        described_class.call(error_log.id, status: 'resolved')
        expect(error_log.reload.resolved).to be true
      end
    end

    context 'with a comment' do
      it 'creates a comment about the status change' do
        expect {
          described_class.call(error_log.id, status: 'in_progress', comment: 'Starting work')
        }.to change(RailsErrorDashboard::ErrorComment, :count).by(1)
      end

      it 'includes the status and comment in the comment body' do
        described_class.call(error_log.id, status: 'in_progress', comment: 'Starting work')
        comment = error_log.comments.last
        expect(comment.body).to include('in_progress')
        expect(comment.body).to include('Starting work')
      end

      it 'sets comment author to assigned user or System' do
        described_class.call(error_log.id, status: 'in_progress', comment: 'test')
        expect(error_log.comments.last.author_name).to eq('System')
      end
    end

    context 'without a comment' do
      it 'does not create a comment' do
        expect {
          described_class.call(error_log.id, status: 'in_progress')
        }.not_to change(RailsErrorDashboard::ErrorComment, :count)
      end
    end

    context 'with invalid transition' do
      it 'returns success false for invalid transition' do
        result = described_class.call(error_log.id, status: 'resolved')
        expect(result[:success]).to be false
      end

      it 'does not change the status' do
        described_class.call(error_log.id, status: 'resolved')
        expect(error_log.reload.status).to eq('new')
      end
    end

    it 'raises ActiveRecord::RecordNotFound for invalid id' do
      expect {
        described_class.call(-1, status: 'in_progress')
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
