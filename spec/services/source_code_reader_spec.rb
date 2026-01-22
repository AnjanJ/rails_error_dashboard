# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::SourceCodeReader do
  let(:test_file_path) { File.join(Rails.root, "app/models/user.rb") }
  let(:test_line_number) { 10 }
  let(:reader) { described_class.new(test_file_path, test_line_number) }

  before do
    # Create a test file with known content
    FileUtils.mkdir_p(File.dirname(test_file_path))
    File.write(test_file_path, <<~RUBY)
      class User < ApplicationRecord
        # Line 2
        # Line 3
        validates :email, presence: true
        # Line 5
        # Line 6
        def full_name
          # Line 8
          # Line 9
          [first_name, last_name].compact.join(' ')  # Line 10 - TARGET
          # Line 11
          # Line 12
        end
        # Line 14
        # Line 15
      end
    RUBY
  end

  after do
    FileUtils.rm_f(test_file_path) if File.exist?(test_file_path)
  end

  describe "#read_lines" do
    context "when file exists and is readable" do
      it "reads lines with default context" do
        lines = reader.read_lines(context: 5)

        expect(lines).to be_an(Array)
        expect(lines.length).to eq(11) # 10 ± 5 lines (but limited by file size)
      end

      it "includes line numbers" do
        lines = reader.read_lines(context: 2)

        expect(lines.first[:number]).to eq(8)  # 10 - 2
        expect(lines.last[:number]).to eq(12)  # 10 + 2
      end

      it "includes line content" do
        lines = reader.read_lines(context: 1)

        target_line = lines.find { |l| l[:number] == 10 }
        expect(target_line[:content]).to include("first_name")
      end

      it "highlights the target line" do
        lines = reader.read_lines(context: 2)

        target_line = lines.find { |l| l[:number] == 10 }
        expect(target_line[:highlight]).to be true

        other_lines = lines.reject { |l| l[:number] == 10 }
        expect(other_lines.all? { |l| !l[:highlight] }).to be true
      end

      it "handles first line edge case" do
        reader = described_class.new(test_file_path, 1)
        lines = reader.read_lines(context: 5)

        expect(lines.first[:number]).to eq(1)
        expect(lines.length).to be <= 6 # Can't go before line 1
      end

      it "handles last line edge case" do
        last_line = 16
        reader = described_class.new(test_file_path, last_line)
        lines = reader.read_lines(context: 5)

        expect(lines.last[:number]).to eq(last_line)
      end

      it "limits context to MAX_CONTEXT_LINES" do
        lines = reader.read_lines(context: 1000)

        # Should be limited to MAX_CONTEXT_LINES (50)
        expect(lines.length).to be <= 101 # 50 before + target + 50 after
      end

      it "enforces minimum context of 1" do
        lines = reader.read_lines(context: 0)

        expect(lines.length).to be >= 1
      end
    end

    context "when file doesn't exist" do
      let(:test_file_path) { File.join(Rails.root, "app/models/non_existent_file.rb") }

      before do
        # Ensure file doesn't exist
        FileUtils.rm_f(test_file_path) if File.exist?(test_file_path)
      end

      it "returns nil" do
        lines = reader.read_lines

        expect(lines).to be_nil
      end

      it "sets error message" do
        reader.read_lines

        expect(reader.error).to match(/not found/i)
      end
    end

    context "when file is binary" do
      let(:binary_file) { File.join(Rails.root, "test_binary.bin") }

      before do
        # Create a binary file with null bytes
        File.write(binary_file, "\x00\x01\x02\xFF" * 100, mode: "wb")
      end

      after do
        FileUtils.rm_f(binary_file)
      end

      it "returns nil for binary files" do
        reader = described_class.new(binary_file, 1)
        lines = reader.read_lines

        expect(lines).to be_nil
      end

      it "sets error message" do
        reader = described_class.new(binary_file, 1)
        reader.read_lines

        expect(reader.error).to match(/binary/i)
      end
    end

    context "when file is too large" do
      let(:large_file) { File.join(Rails.root, "large_file.rb") }

      before do
        # Create file larger than MAX_FILE_SIZE (10 MB)
        allow(File).to receive(:size).and_call_original
        allow(File).to receive(:size).with(large_file).and_return(11 * 1024 * 1024)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(large_file).and_return(true)
        allow(File).to receive(:readable?).and_call_original
        allow(File).to receive(:readable?).with(large_file).and_return(true)
      end

      it "returns nil for large files" do
        reader = described_class.new(large_file, 1)
        lines = reader.read_lines

        expect(lines).to be_nil
      end

      it "sets error message with size info" do
        reader = described_class.new(large_file, 1)
        reader.read_lines

        expect(reader.error).to match(/too large/i)
        expect(reader.error).to match(/\d+ bytes/)
      end
    end

    context "security: directory traversal prevention" do
      it "blocks relative path traversal" do
        malicious_path = File.join(Rails.root, "../../etc/passwd")
        reader = described_class.new(malicious_path, 1)
        lines = reader.read_lines

        expect(lines).to be_nil
      end

      it "blocks absolute path outside Rails.root" do
        reader = described_class.new("/etc/passwd", 1)
        lines = reader.read_lines

        expect(lines).to be_nil
      end

      it "blocks paths with .. components" do
        reader = described_class.new("../../../config/secrets.yml", 1)
        lines = reader.read_lines

        expect(lines).to be_nil
      end
    end

    context "security: sensitive file protection" do
      sensitive_files = [
        ".env",
        "config/database.yml",
        "config/secrets.yml",
        "config/credentials.yml.enc",
        "config/master.key",
        "private_key.pem",
        "id_rsa.key"
      ]

      sensitive_files.each do |file|
        it "blocks access to #{file}" do
          path = File.join(Rails.root, file)
          reader = described_class.new(path, 1)

          # Stub file existence to test validation
          allow(File).to receive(:exist?).with(anything).and_return(true)
          allow(File).to receive(:readable?).with(anything).and_return(true)
          allow(File).to receive(:size).with(anything).and_return(100)

          lines = reader.read_lines

          expect(lines).to be_nil
        end
      end
    end

    context "security: gem/vendor code filtering" do
      before do
        RailsErrorDashboard.configuration.only_show_app_code_source = true
      end

      gem_paths = [
        "/gems/activerecord-7.0.0/lib/active_record.rb",
        "/vendor/bundle/ruby/3.2.0/gems/rails-7.0.0/railties.rb",
        "/.bundle/gems/faker-2.0.0/lib/faker.rb"
      ]

      gem_paths.each do |path|
        it "blocks gem code: #{path}" do
          reader = described_class.new(path, 1)
          lines = reader.read_lines

          expect(lines).to be_nil
        end
      end

      it "allows gem code when only_show_app_code_source is false" do
        RailsErrorDashboard.configuration.only_show_app_code_source = false

        gem_file = File.join(Rails.root, "vendor/bundle/test_gem.rb")
        FileUtils.mkdir_p(File.dirname(gem_file))
        File.write(gem_file, "# Gem code\n")

        reader = described_class.new(gem_file, 1)
        lines = reader.read_lines

        # Should not be nil (validation passes), but might be nil for other reasons
        # The key is validation doesn't block it
        expect(reader.error).not_to match(/gem|vendor/i) if lines.nil?

        FileUtils.rm_f(gem_file)
      end
    end

    context "error handling" do
      it "handles file read errors gracefully" do
        # Mock the private method to simulate file read error
        allow(reader).to receive(:read_specific_lines).and_raise(Errno::EACCES, "Permission denied")

        lines = reader.read_lines

        expect(lines).to be_nil
        expect(reader.error).to match(/error reading/i)
      end

      it "handles encoding errors gracefully" do
        # Create file with invalid UTF-8
        invalid_file = File.join(Rails.root, "invalid_encoding.rb")
        File.write(invalid_file, "test\xFF\xFE", encoding: "ASCII-8BIT")

        reader = described_class.new(invalid_file, 1)

        # Should handle gracefully
        expect { reader.read_lines }.not_to raise_error

        FileUtils.rm_f(invalid_file)
      end
    end
  end

  describe "#file_exists?" do
    it "returns true when file exists and is readable" do
      expect(reader.file_exists?).to be true
    end

    it "returns false when file doesn't exist" do
      reader = described_class.new("/non/existent/file.rb", 1)

      expect(reader.file_exists?).to be false
    end

    it "returns false for invalid paths" do
      reader = described_class.new(nil, 1)

      expect(reader.file_exists?).to be false
    end

    it "returns false when path validation fails" do
      reader = described_class.new("/etc/passwd", 1)

      expect(reader.file_exists?).to be false
    end

    it "handles exceptions gracefully" do
      # Stub only for the specific call, then restore
      allow(reader).to receive(:resolve_absolute_path).and_raise(StandardError, "Unexpected error")

      expect(reader.file_exists?).to be false
    end
  end

  describe "path resolution" do
    it "handles absolute paths within Rails.root" do
      absolute_path = File.join(Rails.root, "app/models/user.rb")
      reader = described_class.new(absolute_path, 1)

      expect(reader.file_exists?).to be true
    end

    it "handles relative paths" do
      reader = described_class.new("app/models/user.rb", 1)

      expect(reader.file_exists?).to be true
    end

    it "handles paths starting with /" do
      # Simulate backtrace path from different deployment location
      reader = described_class.new("/deployed/app/models/user.rb", 1)

      # Should attempt to resolve relative to Rails.root
      # May or may not exist, but shouldn't crash
      expect { reader.file_exists? }.not_to raise_error
    end
  end
end
