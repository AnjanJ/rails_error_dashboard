# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::ErrorHashGenerator do
  def make_exception(klass, message, backtrace = nil)
    error = klass.new(message)
    error.set_backtrace(backtrace || [ "#{Rails.root}/app/controllers/users_controller.rb:10:in `show'" ])
    error
  end

  describe ".call" do
    it "returns a 16-character hex string" do
      error = make_exception(NoMethodError, "undefined method 'foo'")
      result = described_class.call(error)

      expect(result).to be_a(String)
      expect(result.length).to eq(16)
      expect(result).to match(/\A[0-9a-f]+\z/)
    end

    it "produces same hash for same error" do
      error1 = make_exception(NoMethodError, "undefined method 'foo'")
      error2 = make_exception(NoMethodError, "undefined method 'foo'")

      expect(described_class.call(error1)).to eq(described_class.call(error2))
    end

    it "produces different hash for different error types" do
      error1 = make_exception(NoMethodError, "test")
      error2 = make_exception(ArgumentError, "test")

      expect(described_class.call(error1)).not_to eq(described_class.call(error2))
    end

    it "produces different hash for different controller contexts" do
      error = make_exception(NoMethodError, "test")

      hash1 = described_class.call(error, controller_name: "users")
      hash2 = described_class.call(error, controller_name: "posts")

      expect(hash1).not_to eq(hash2)
    end

    it "produces different hash for different applications" do
      error = make_exception(NoMethodError, "test")

      hash1 = described_class.call(error, application_id: 1)
      hash2 = described_class.call(error, application_id: 2)

      expect(hash1).not_to eq(hash2)
    end

    it "normalizes dynamic values in messages" do
      error1 = make_exception(NoMethodError, "User 123 not found")
      error2 = make_exception(NoMethodError, "User 456 not found")

      expect(described_class.call(error1)).to eq(described_class.call(error2))
    end
  end

  describe ".normalize_message" do
    it "replaces numbers with N" do
      expect(described_class.normalize_message("User 123")).to eq("User N")
    end

    it "replaces double-quoted strings" do
      expect(described_class.normalize_message('key "foo"')).to eq('key ""')
    end

    it "replaces single-quoted strings" do
      expect(described_class.normalize_message("key 'foo'")).to eq("key ''")
    end

    it "replaces hex addresses" do
      expect(described_class.normalize_message("object at 0x7fff")).to eq("object at HEX")
    end

    it "replaces object inspections" do
      expect(described_class.normalize_message("got #<User:0x123>")).to eq("got #<OBJ>")
    end

    it "returns nil for nil input" do
      expect(described_class.normalize_message(nil)).to be_nil
    end
  end

  describe ".from_attributes" do
    let(:backtrace) { "app/models/user.rb:10:in `name'\napp/controllers/users_controller.rb:5:in `show'" }

    it "returns a 16-character hex string" do
      result = described_class.from_attributes(error_type: "NoMethodError", message: "test")

      expect(result).to be_a(String)
      expect(result.length).to eq(16)
      expect(result).to match(/\A[0-9a-f]+\z/)
    end

    it "produces same hash for same attributes" do
      hash1 = described_class.from_attributes(error_type: "NoMethodError", message: "test", backtrace: backtrace)
      hash2 = described_class.from_attributes(error_type: "NoMethodError", message: "test", backtrace: backtrace)

      expect(hash1).to eq(hash2)
    end

    it "produces different hash for different error types" do
      hash1 = described_class.from_attributes(error_type: "NoMethodError", message: "test")
      hash2 = described_class.from_attributes(error_type: "ArgumentError", message: "test")

      expect(hash1).not_to eq(hash2)
    end

    it "produces different hash for different controllers" do
      hash1 = described_class.from_attributes(error_type: "NoMethodError", controller_name: "users")
      hash2 = described_class.from_attributes(error_type: "NoMethodError", controller_name: "posts")

      expect(hash1).not_to eq(hash2)
    end

    it "produces different hash for different actions" do
      hash1 = described_class.from_attributes(error_type: "NoMethodError", action_name: "show")
      hash2 = described_class.from_attributes(error_type: "NoMethodError", action_name: "create")

      expect(hash1).not_to eq(hash2)
    end

    it "produces different hash for different applications" do
      hash1 = described_class.from_attributes(error_type: "NoMethodError", application_id: 1)
      hash2 = described_class.from_attributes(error_type: "NoMethodError", application_id: 2)

      expect(hash1).not_to eq(hash2)
    end

    it "normalizes dynamic values using ErrorNormalizer" do
      hash1 = described_class.from_attributes(error_type: "NoMethodError", message: "User #123 not found")
      hash2 = described_class.from_attributes(error_type: "NoMethodError", message: "User #456 not found")

      expect(hash1).to eq(hash2)
    end

    it "extracts significant backtrace frames" do
      bt = "app/models/user.rb:10:in `name'\nvendor/bundle/gems/activesupport/lib/core.rb:5:in `call'"
      hash1 = described_class.from_attributes(error_type: "NoMethodError", backtrace: bt)
      hash2 = described_class.from_attributes(error_type: "NoMethodError", backtrace: nil)

      expect(hash1).not_to eq(hash2)
    end

    it "handles nil message gracefully" do
      result = described_class.from_attributes(error_type: "NoMethodError", message: nil)
      expect(result).to be_a(String)
      expect(result.length).to eq(16)
    end

    it "handles nil backtrace gracefully" do
      result = described_class.from_attributes(error_type: "NoMethodError", backtrace: nil)
      expect(result).to be_a(String)
      expect(result.length).to eq(16)
    end
  end

  describe ".extract_app_frame" do
    it "finds app code frames" do
      backtrace = [
        "/gems/activerecord/lib/connection.rb:10:in `query'",
        "#{Rails.root}/app/models/user.rb:5:in `find'",
        "#{Rails.root}/app/controllers/users_controller.rb:10:in `show'"
      ]

      result = described_class.extract_app_frame(backtrace)
      expect(result).to include("app/models/user.rb")
    end

    it "returns nil for nil backtrace" do
      expect(described_class.extract_app_frame(nil)).to be_nil
    end

    it "returns nil for empty backtrace" do
      expect(described_class.extract_app_frame([])).to be_nil
    end
  end
end
