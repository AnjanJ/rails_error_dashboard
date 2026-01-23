# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Helpers::UserModelDetector do
  describe ".detect_user_model" do
    context "when user_model is explicitly configured" do
      before do
        RailsErrorDashboard.configuration.user_model = "Account"
      end

      after do
        RailsErrorDashboard.configuration.user_model = nil
      end

      it "returns the configured model" do
        expect(described_class.detect_user_model).to eq("Account")
      end
    end

    context "when user_model is not configured" do
      before do
        RailsErrorDashboard.configuration.user_model = nil
      end

      it "returns 'User' if User model exists" do
        allow(described_class).to receive(:user_model_exists?).and_return(true)
        expect(described_class.detect_user_model).to eq("User")
      end

      it "checks for alternative models if User doesn't exist" do
        allow(described_class).to receive(:user_model_exists?).and_return(false)
        allow(described_class).to receive(:model_exists?).with("Account").and_return(true)

        expect(described_class.detect_user_model).to eq("Account")
      end

      it "returns nil if no user model found" do
        allow(described_class).to receive(:user_model_exists?).and_return(false)
        allow(described_class).to receive(:model_exists?).and_return(false)

        expect(described_class.detect_user_model).to be_nil
      end
    end

    context "when user_model is set to default 'User'" do
      before do
        RailsErrorDashboard.configuration.user_model = "User"
      end

      after do
        RailsErrorDashboard.configuration.user_model = nil
      end

      it "still attempts auto-detection" do
        allow(described_class).to receive(:user_model_exists?).and_return(true)
        expect(described_class.detect_user_model).to eq("User")
      end
    end
  end

  describe ".detect_total_users" do
    context "when total_users_for_impact is explicitly configured" do
      before do
        RailsErrorDashboard.configuration.total_users_for_impact = 1000
      end

      after do
        RailsErrorDashboard.configuration.total_users_for_impact = nil
      end

      it "returns the configured value" do
        expect(described_class.detect_total_users).to eq(1000)
      end
    end

    context "when total_users_for_impact is not configured" do
      before do
        RailsErrorDashboard.configuration.total_users_for_impact = nil
      end

      it "queries the user model count" do
        allow(described_class).to receive(:detect_user_model).and_return("User")
        allow(described_class).to receive(:query_user_count).with("User").and_return(500)

        expect(described_class.detect_total_users).to eq(500)
      end

      it "returns nil if no user model found" do
        allow(described_class).to receive(:detect_user_model).and_return(nil)

        expect(described_class.detect_total_users).to be_nil
      end

      it "returns nil if query fails" do
        allow(described_class).to receive(:detect_user_model).and_return("User")
        allow(described_class).to receive(:query_user_count).and_raise(StandardError.new("DB error"))

        expect(described_class.detect_total_users).to be_nil
      end
    end
  end

  describe ".user_model_exists?" do
    it "returns true if User model file exists and is loadable" do
      allow(described_class).to receive(:model_file_exists?).with("User").and_return(true)
      allow(described_class).to receive(:model_exists?).with("User").and_return(true)

      expect(described_class.user_model_exists?).to be true
    end

    it "returns false if User model doesn't exist" do
      allow(described_class).to receive(:model_exists?).with("User").and_return(false)

      expect(described_class.user_model_exists?).to be false
    end
  end

  describe ".model_exists?" do
    it "returns true for existing ActiveRecord models in engine namespace" do
      # Since we're in an engine, check if file detection works
      allow(described_class).to receive(:model_file_exists?).with("RailsErrorDashboard::ErrorLog").and_return(true)

      expect(described_class.model_exists?("RailsErrorDashboard::ErrorLog")).to be true
    end

    it "returns false for non-existent models" do
      allow(described_class).to receive(:model_file_exists?).with("NonExistentModel").and_return(false)

      expect(described_class.model_exists?("NonExistentModel")).to be false
    end

    it "returns false if constantize raises NameError" do
      allow(described_class).to receive(:model_file_exists?).with("BrokenModel").and_return(true)
      stub_const("BrokenModel", nil)
      allow(described_class).to receive(:model_exists?).and_call_original

      expect(described_class.model_exists?("BrokenModel")).to be false
    end
  end

  describe ".model_file_exists?" do
    it "returns true if model file exists in app/models" do
      allow(Rails).to receive(:root).and_return(Pathname.new("/app"))
      allow(File).to receive(:exist?).with(Pathname.new("/app/app/models/user.rb")).and_return(true)

      expect(described_class.model_file_exists?("User")).to be true
    end

    it "returns false if model file doesn't exist" do
      allow(Rails).to receive(:root).and_return(Pathname.new("/app"))
      allow(File).to receive(:exist?).with(Pathname.new("/app/app/models/non_existent.rb")).and_return(false)

      expect(described_class.model_file_exists?("NonExistent")).to be false
    end

    it "returns false if Rails is not defined" do
      hide_const("Rails")

      expect(described_class.model_file_exists?("User")).to be false
    end
  end

  describe ".query_user_count" do
    let(:mock_model) { class_double("User", count: 100) }

    before do
      stub_const("User", mock_model)
    end

    it "returns the count from the model" do
      expect(described_class.query_user_count("User")).to eq(100)
    end

    it "returns nil if model doesn't respond to count" do
      allow(mock_model).to receive(:respond_to?).with(:count).and_return(false)

      expect(described_class.query_user_count("User")).to be_nil
    end

    it "returns nil if model doesn't exist" do
      expect(described_class.query_user_count("NonExistentModel")).to be_nil
    end

    it "returns nil on timeout" do
      allow(mock_model).to receive(:count).and_raise(Timeout::Error)

      expect(described_class.query_user_count("User")).to be_nil
    end

    it "returns nil on database error" do
      allow(mock_model).to receive(:count).and_raise(ActiveRecord::StatementInvalid.new("DB error"))

      expect(described_class.query_user_count("User")).to be_nil
    end
  end

  describe ".calculate_user_impact" do
    before do
      RailsErrorDashboard.configuration.total_users_for_impact = 1000
    end

    after do
      RailsErrorDashboard.configuration.total_users_for_impact = nil
    end

    it "calculates percentage when total users is available" do
      allow(described_class).to receive(:detect_total_users).and_return(1000)

      expect(described_class.calculate_user_impact(50)).to eq(5.0)
    end

    it "returns nil if unique_users_count is nil" do
      expect(described_class.calculate_user_impact(nil)).to be_nil
    end

    it "returns nil if unique_users_count is zero" do
      expect(described_class.calculate_user_impact(0)).to be_nil
    end

    it "returns nil if total users is not available" do
      allow(described_class).to receive(:detect_total_users).and_return(nil)

      expect(described_class.calculate_user_impact(50)).to be_nil
    end

    it "returns nil if total users is zero" do
      allow(described_class).to receive(:detect_total_users).and_return(0)

      expect(described_class.calculate_user_impact(50)).to be_nil
    end

    it "rounds to 2 decimal places" do
      allow(described_class).to receive(:detect_total_users).and_return(1000)

      expect(described_class.calculate_user_impact(123)).to eq(12.3)
    end
  end
end
