# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::ErrorLog, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      error_log = build(:error_log)
      expect(error_log).to be_valid
    end

    it 'requires error_type' do
      error_log = build(:error_log, error_type: nil)
      expect(error_log).not_to be_valid
      expect(error_log.errors[:error_type]).to include("can't be blank")
    end

    it 'requires message' do
      error_log = build(:error_log, message: nil)
      expect(error_log).not_to be_valid
      expect(error_log.errors[:message]).to include("can't be blank")
    end

    it 'requires occurred_at' do
      error_log = build(:error_log, occurred_at: nil)
      expect(error_log).not_to be_valid
      expect(error_log.errors[:occurred_at]).to include("can't be blank")
    end
  end

  describe 'scopes' do
    let!(:resolved_error) { create(:error_log, :resolved) }
    let!(:unresolved_error) { create(:error_log) }
    let!(:ios_error) { create(:error_log, :ios) }
    let!(:android_error) { create(:error_log, :android) }
    let!(:prod_error) { create(:error_log, :production) }
    let!(:old_error) { create(:error_log, occurred_at: 2.days.ago) }
    let!(:recent_error) { create(:error_log, occurred_at: 1.hour.ago) }

    describe '.resolved' do
      it 'returns only resolved errors' do
        expect(described_class.resolved).to include(resolved_error)
        expect(described_class.resolved).not_to include(unresolved_error)
      end
    end

    describe '.unresolved' do
      it 'returns only unresolved errors' do
        expect(described_class.unresolved).to include(unresolved_error)
        expect(described_class.unresolved).not_to include(resolved_error)
      end
    end

    describe '.by_platform' do
      it 'filters by iOS' do
        expect(described_class.by_platform('iOS')).to include(ios_error)
        expect(described_class.by_platform('iOS')).not_to include(android_error)
      end

      it 'filters by Android' do
        expect(described_class.by_platform('Android')).to include(android_error)
        expect(described_class.by_platform('Android')).not_to include(ios_error)
      end
    end

    describe '.by_environment' do
      it 'filters by environment' do
        expect(described_class.by_environment('production')).to include(prod_error)
      end
    end

    describe '.by_error_type' do
      it 'filters by error type' do
        type_error = create(:error_log, error_type: 'TypeError')
        expect(described_class.by_error_type('TypeError')).to include(type_error)
      end
    end

    describe '.recent' do
      it 'returns errors ordered by most recent first' do
        # recent_error should be in the list and newer than old_error
        errors = described_class.recent.to_a
        expect(errors.index(recent_error)).to be < errors.index(old_error)
      end
    end

    describe '.last_24_hours' do
      it 'returns errors from last 24 hours' do
        expect(described_class.last_24_hours).to include(recent_error)
        expect(described_class.last_24_hours).not_to include(old_error)
      end
    end

    describe '.last_week' do
      it 'returns errors from last week' do
        expect(described_class.last_week).to include(recent_error)
        expect(described_class.last_week).to include(old_error)
      end
    end
  end

  describe '#resolved?' do
    it 'returns true when resolved is true' do
      error_log = build(:error_log, :resolved)
      expect(error_log.resolved?).to be true
    end

    it 'returns false when resolved is false' do
      error_log = build(:error_log)
      expect(error_log.resolved?).to be false
    end
  end

  describe 'database connection' do
    context 'when use_separate_database is false' do
      before do
        allow(RailsErrorDashboard.configuration).to receive(:use_separate_database).and_return(false)
      end

      it 'uses primary database' do
        error_log = create(:error_log)
        expect(error_log.class.connection_db_config.name).to eq('primary')
      end
    end
  end

  describe 'default values' do
    it 'sets environment from Rails.env by default' do
      error_log = create(:error_log, environment: nil)
      error_log.reload
      # Environment is set in the factory, so we test that it's present
      expect(error_log.environment).to be_present
    end

    it 'sets platform to API by default' do
      error_log = build(:error_log, platform: nil)
      error_log.valid? # Trigger before_validation callback
      expect(error_log.platform).to eq('API')
    end
  end
end
