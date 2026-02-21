# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::EnvironmentSnapshot do
  after { described_class.reset! }

  describe ".snapshot" do
    it "returns a hash with required keys" do
      result = described_class.snapshot

      expect(result).to be_a(Hash)
      expect(result).to have_key(:ruby_version)
      expect(result).to have_key(:ruby_engine)
      expect(result).to have_key(:ruby_platform)
      expect(result).to have_key(:rails_version)
      expect(result).to have_key(:rails_env)
      expect(result).to have_key(:gem_versions)
      expect(result).to have_key(:server)
      expect(result).to have_key(:database_adapter)
    end

    it "captures the correct Ruby version" do
      result = described_class.snapshot
      expect(result[:ruby_version]).to eq(RUBY_VERSION)
    end

    it "captures the correct Ruby engine" do
      result = described_class.snapshot
      expect(result[:ruby_engine]).to eq(RUBY_ENGINE)
    end

    it "captures the correct Ruby platform" do
      result = described_class.snapshot
      expect(result[:ruby_platform]).to eq(RUBY_PLATFORM)
    end

    it "captures the correct Rails version" do
      result = described_class.snapshot
      expect(result[:rails_version]).to eq(Rails.version)
    end

    it "captures Rails environment as a string" do
      result = described_class.snapshot
      expect(result[:rails_env]).to be_a(String)
      expect(result[:rails_env]).to eq(Rails.env.to_s)
    end

    it "captures gem versions as a hash" do
      result = described_class.snapshot
      expect(result[:gem_versions]).to be_a(Hash)
    end

    it "includes activerecord in gem versions" do
      result = described_class.snapshot
      expect(result[:gem_versions]).to have_key("activerecord")
      expect(result[:gem_versions]["activerecord"]).to eq(ActiveRecord.version.to_s)
    end

    it "only includes loaded gems from the tracked list" do
      result = described_class.snapshot
      result[:gem_versions].each_key do |gem_name|
        expect(Gem.loaded_specs).to have_key(gem_name)
      end
    end

    it "detects the web server" do
      result = described_class.snapshot
      expect(result[:server]).to be_a(String)
    end

    it "detects the database adapter" do
      result = described_class.snapshot
      expect(result[:database_adapter]).to be_a(String)
      expect(result[:database_adapter]).not_to eq("unknown")
    end

    it "caches the result across calls" do
      first = described_class.snapshot
      second = described_class.snapshot
      expect(first).to equal(second) # same object identity
    end

    it "returns a frozen hash" do
      result = described_class.snapshot
      expect(result).to be_frozen
    end

    it "is serializable to JSON" do
      result = described_class.snapshot
      json = result.to_json
      parsed = JSON.parse(json)
      expect(parsed["ruby_version"]).to eq(RUBY_VERSION)
      expect(parsed["rails_version"]).to eq(Rails.version)
    end
  end

  describe ".reset!" do
    it "clears the cached snapshot" do
      first = described_class.snapshot
      described_class.reset!
      second = described_class.snapshot
      expect(first).not_to equal(second) # different object identity
    end
  end
end
