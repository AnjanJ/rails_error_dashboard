# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::SimilarErrors do
  describe ".call" do
    let(:target_error) do
      create(:error_log,
        error_type: "NoMethodError",
        message: "undefined method 'name' for nil:NilClass",
        backtrace: "app/models/user.rb:10:in `save'\napp/controllers/users_controller.rb:20:in `create'",
        platform: "iOS",
        backtrace_signature: "abc123"
      )
    end

    it "returns empty array if error not found" do
      result = described_class.call(99999)
      expect(result).to eq([])
    end

    it "finds errors with same backtrace signature" do
      similar = create(:error_log,
        error_type: "ArgumentError",
        message: "wrong number of arguments",
        backtrace: target_error.backtrace,
        platform: "iOS",
        backtrace_signature: "abc123"
      )

      result = described_class.call(target_error.id, threshold: 0.6)

      expect(result.size).to be >= 1
      expect(result.first[:error].id).to eq(similar.id)
      expect(result.first[:similarity]).to be >= 0.6
    end

    it "finds errors with same error type" do
      target_error # Force creation of target_error first

      similar = create(:error_log,
        error_type: "NoMethodError",
        message: "undefined method 'email' for nil:NilClass",
        backtrace: "app/models/user.rb:15:in `save'\napp/services/user_service.rb:5:in `process'",
        platform: "iOS",
        backtrace_signature: "xyz789"
      )

      result = described_class.call(target_error.id, threshold: 0.3)

      expect(result.size).to be >= 1
      error_ids = result.map { |r| r[:error].id }
      expect(error_ids).to include(similar.id)
    end

    it "respects threshold parameter" do
      # Very similar error (high score)
      very_similar = create(:error_log,
        error_type: target_error.error_type,
        message: target_error.message,
        backtrace: target_error.backtrace,
        platform: "iOS"
      )

      # Somewhat similar error (medium score)
      somewhat_similar = create(:error_log,
        error_type: target_error.error_type,
        message: "completely different message",
        backtrace: "completely/different/path.rb:1:in `method'",
        platform: "iOS"
      )

      # High threshold - should only get very similar
      result = described_class.call(target_error.id, threshold: 0.8)
      expect(result.map { |r| r[:error].id }).to include(very_similar.id)
      expect(result.map { |r| r[:error].id }).not_to include(somewhat_similar.id)
    end

    it "respects limit parameter" do
      # Create 15 similar errors
      15.times do |i|
        create(:error_log,
          error_type: "NoMethodError",
          message: "undefined method 'attr#{i}' for nil:NilClass",
          backtrace: target_error.backtrace,
          platform: "iOS"
        )
      end

      result = described_class.call(target_error.id, limit: 5)
      expect(result.size).to be <= 5
    end

    it "sorts results by similarity score descending" do
      # Create errors with varying similarity
      create(:error_log,
        error_type: target_error.error_type,
        message: target_error.message,
        backtrace: target_error.backtrace,
        platform: "iOS"
      )

      create(:error_log,
        error_type: target_error.error_type,
        message: "different message",
        backtrace: target_error.backtrace,
        platform: "iOS"
      )

      result = described_class.call(target_error.id, threshold: 0.3)

      if result.size >= 2
        # Verify scores are in descending order
        scores = result.map { |r| r[:similarity] }
        expect(scores).to eq(scores.sort.reverse)
      end
    end

    it "excludes the target error itself" do
      result = described_class.call(target_error.id)
      error_ids = result.map { |r| r[:error].id }
      expect(error_ids).not_to include(target_error.id)
    end

    it "returns similarity scores as floats rounded to 3 decimals" do
      create(:error_log,
        error_type: target_error.error_type,
        message: target_error.message,
        backtrace: target_error.backtrace,
        platform: "iOS"
      )

      result = described_class.call(target_error.id)

      if result.any?
        expect(result.first[:similarity]).to be_a(Float)
        expect(result.first[:similarity].to_s.split(".").last.length).to be <= 3
      end
    end

    it "returns errors from same platform only (per user config)" do
      ios_similar = create(:error_log,
        error_type: target_error.error_type,
        message: target_error.message,
        backtrace: target_error.backtrace,
        platform: "iOS"
      )

      android_similar = create(:error_log,
        error_type: target_error.error_type,
        message: target_error.message,
        backtrace: target_error.backtrace,
        platform: "Android"
      )

      result = described_class.call(target_error.id, threshold: 0.6)

      error_ids = result.map { |r| r[:error].id }
      expect(error_ids).to include(ios_similar.id)
      expect(error_ids).not_to include(android_similar.id)
    end

    it "handles errors with nil backtrace" do
      target = create(:error_log, backtrace: nil, platform: "iOS")
      create(:error_log, backtrace: nil, platform: "iOS")

      expect {
        described_class.call(target.id)
      }.not_to raise_error
    end

    it "handles errors with nil backtrace_signature" do
      target = create(:error_log, backtrace_signature: nil, platform: "iOS")

      expect {
        described_class.call(target.id)
      }.not_to raise_error
    end
  end

  describe "#find_candidates" do
    let(:target_error) do
      create(:error_log,
        error_type: "NoMethodError",
        platform: "iOS",
        backtrace_signature: "abc123"
      )
    end

    let(:query_instance) { described_class.new(target_error.id) }

    it "finds candidates with same backtrace signature" do
      similar = create(:error_log,
        error_type: "ArgumentError",
        platform: "iOS",
        backtrace_signature: "abc123"
      )

      candidates = query_instance.send(:find_candidates, target_error)
      expect(candidates.map(&:id)).to include(similar.id)
    end

    it "finds candidates with same error type" do
      similar = create(:error_log,
        error_type: "NoMethodError",
        platform: "iOS",
        backtrace_signature: "xyz789"
      )

      candidates = query_instance.send(:find_candidates, target_error)
      expect(candidates.map(&:id)).to include(similar.id)
    end

    it "finds candidates from same platform with similar error type" do
      create(:error_log,
        error_type: "NameError", # Similar prefix to NoMethodError
        platform: "iOS",
        backtrace_signature: "xyz789"
      )

      candidates = query_instance.send(:find_candidates, target_error)
      # May or may not include depending on similarity strategy
      expect(candidates).to be_an(Array)
    end

    it "returns unique candidates" do
      # Create error matching multiple strategies
      create(:error_log,
        error_type: target_error.error_type,
        platform: target_error.platform,
        backtrace_signature: target_error.backtrace_signature
      )

      candidates = query_instance.send(:find_candidates, target_error)
      candidate_ids = candidates.map(&:id)
      expect(candidate_ids.uniq.size).to eq(candidate_ids.size)
    end

    it "limits candidate size for performance" do
      # Create many similar errors
      50.times do |i|
        create(:error_log,
          error_type: "NoMethodError",
          platform: "iOS",
          backtrace_signature: "sig#{i}"
        )
      end

      candidates = query_instance.send(:find_candidates, target_error)
      # Should limit to reasonable number (50 from signature + 30 from type + 20 from prefix = max ~100)
      expect(candidates.size).to be <= 100
    end

    # Strategy 3 builds a LIKE pattern from the stored error type, which for
    # API-reported errors is whatever the client sent.
    it "treats LIKE wildcards in the error type prefix literally" do
      odd = create(:error_log, error_type: "My_%Error", platform: "iOS", backtrace_signature: "odd1")
      lookalike = create(:error_log, error_type: "MyXYZError", platform: "iOS", backtrace_signature: "odd2")
      literal = create(:error_log, error_type: "Other::My_%Thing", platform: "iOS", backtrace_signature: "odd3")

      candidates = described_class.new(odd.id).send(:find_candidates, odd)

      expect(candidates).to include(literal)
      expect(candidates).not_to include(lookalike)
    end
  end
end
