# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Commands::AddErrorComment do
  describe '.call' do
    let(:error_log) { create(:error_log) }

    it 'creates a comment on the error' do
      expect {
        described_class.call(error_log.id, author_name: 'gandalf', body: 'Looking into this')
      }.to change(RailsErrorDashboard::ErrorComment, :count).by(1)
    end

    it 'sets the correct author name' do
      described_class.call(error_log.id, author_name: 'gandalf', body: 'test')
      expect(error_log.comments.last.author_name).to eq('gandalf')
    end

    it 'sets the correct body' do
      described_class.call(error_log.id, author_name: 'gandalf', body: 'Looking into this')
      expect(error_log.comments.last.body).to eq('Looking into this')
    end

    it 'returns the error log' do
      result = described_class.call(error_log.id, author_name: 'gandalf', body: 'test')
      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result.id).to eq(error_log.id)
    end

    it 'raises ActiveRecord::RecordNotFound for invalid id' do
      expect {
        described_class.call(-1, author_name: 'gandalf', body: 'test')
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'raises on blank body' do
      expect {
        described_class.call(error_log.id, author_name: 'gandalf', body: '')
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
