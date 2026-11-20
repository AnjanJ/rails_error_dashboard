# frozen_string_literal: true

require "rails_helper"
require "shellwords"
require "tmpdir"

# The v2 fingerprint recipe and ErrorHashGenerator.identities.
# See .shipkit/specs/hardening-1-0-rc2 (REQ-1 to REQ-4, REQ-7; REQ-2 amended
# 2026-11-20 to skip a C method's frame reported at its caller's line).
module ErrorHashGeneratorV2Fixtures
  def self.two_lines(flag)
    raise ArgumentError, "boom" if flag
    raise ArgumentError, "boom"
  end

  def self.first_method
    raise ArgumentError, "boom"
  end

  def self.second_method
    raise ArgumentError, "boom"
  end

  def self.load_user(params) = params.fetch(:id)
  def self.load_order(params) = params.fetch(:id)

  def self.parse_a(value) = Integer(value)
  def self.parse_b(value) = Integer(value)

  def self.send_to_nil(name) = nil.public_send(name)

  def self.split_words(text) = Shellwords.split(text)
end

RSpec.describe RailsErrorDashboard::Services::ErrorHashGenerator, ".identities" do
  let(:fixtures) { ErrorHashGeneratorV2Fixtures }

  def capture
    yield
    raise "expected the block to raise"
  rescue => e
    e
  end

  def identities(exception, context = {})
    described_class.identities(exception, context)
  end

  # An exception with the same class, message, name and backtrace strings, but
  # no backtrace_locations: a backtrace set from strings.
  def strings_only(exception)
    copy = exception.is_a?(NameError) ? exception.class.new(exception.message, exception.name) : exception.class.new(exception.message)
    copy.set_backtrace(exception.backtrace)
    copy
  end

  describe "the result" do
    it "returns opaque 16-character v2 and v1 identities and no custom value" do
      result = identities(capture { fixtures.first_method })

      expect(result.keys).to contain_exactly(:v2, :v1, :custom)
      expect(result[:v2]).to match(/\A[0-9a-f]{16}\z/)
      expect(result[:v1]).to match(/\A[0-9a-f]{16}\z/)
      expect(result[:custom]).to be_nil
      expect(result[:v2]).not_to eq(result[:v1])
    end

    it "gives v1 equal to rc.1's ErrorHashGenerator.call once completed with the application (hardening-1-0-rc2/REQ-5)" do
      error = capture { fixtures.first_method }
      context = { controller_name: "users", action_name: "show" }

      completed = described_class.complete(identities(error, context)[:v1], 7)
      rc1 = described_class.call(error, controller_name: "users", action_name: "show", application_id: 7)

      expect(completed).to eq(rc1)
    end
  end

  describe "the app frame's path, relative to Rails.root (hardening-1-0-rc2/REQ-1)" do
    around do |example|
      Dir.mktmpdir("red-v2-") do |tmp|
        @tmp = File.realpath(tmp)
        example.run
      end
    end

    # The same file, deployed to a new release directory, as Capistrano does.
    def deploy(release)
      dir = File.join(@tmp, "releases", release)
      FileUtils.mkdir_p(File.join(dir, "app/services"))
      File.write(File.join(dir, "app/services/widget_service.rb"), <<~RUBY)
        module ErrorHashGeneratorV2Widget
          def self.explode
            raise ArgumentError, "widget 42 failed"
          end
        end
      RUBY
      dir
    end

    def raise_from(dir, root:)
      silence_warnings { load File.join(dir, "app/services/widget_service.rb") }
      error = capture { ErrorHashGeneratorV2Widget.explode }
      allow(Rails).to receive(:root).and_return(Pathname.new(root))
      identities(error)
    end

    it "gives one v2 identity for one file loaded from two release directories" do
      first = deploy("20261101000000")
      second = deploy("20261102000000")

      from_first = raise_from(first, root: first)
      from_second = raise_from(second, root: second)

      expect(from_second[:v2]).to eq(from_first[:v2])
      expect(from_second[:v1]).not_to eq(from_first[:v1]) # rc.1 split them
    end

    it "gives the same v2 identity when Rails.root is a symlink to the release" do
      release = deploy("20261102000000")
      current = File.join(@tmp, "current")
      File.symlink(release, current)

      through_release = raise_from(release, root: release)
      through_symlink_root = raise_from(release, root: current)
      loaded_through_symlink = raise_from(current, root: current)

      expect(through_symlink_root[:v2]).to eq(through_release[:v2])
      expect(loaded_through_symlink[:v2]).to eq(through_release[:v2])
    end
  end

  describe "frames that are not the app's (hardening-1-0-rc2/REQ-2)" do
    it "skips an <internal: frame" do
      error = capture { fixtures.parse_a("x") }
      other = capture { fixtures.parse_b("x") }

      expect(identities(error)[:v2]).not_to eq(identities(other)[:v2])
    end

    it "skips frames under Ruby's own library directory" do
      error = capture { fixtures.split_words("a 'b") }
      expect(error.backtrace_locations.first.path).to start_with(RbConfig::CONFIG["rubylibdir"])

      same_method = capture { fixtures.split_words("c 'd") }
      expect(identities(error)[:v2]).to eq(identities(same_method)[:v2])

      direct = capture { Shellwords.split("a 'b") }
      expect(identities(error)[:v2]).not_to eq(identities(direct)[:v2])
    end

    it "skips a C method's frame reported at its caller's line" do
      user = capture { fixtures.load_user({}) }
      order = capture { fixtures.load_order({}) }

      expect(user.message).to eq(order.message)
      expect(identities(user)[:v2]).not_to eq(identities(order)[:v2])
      expect(identities(user)[:v1]).to eq(identities(order)[:v1]) # rc.1 merged them
    end
  end

  describe "the app frame's method, without its line (hardening-1-0-rc2/REQ-3)" do
    it "gives one v2 identity for one method raising at two lines" do
      at_first_line = capture { fixtures.two_lines(true) }
      at_second_line = capture { fixtures.two_lines(false) }

      expect(at_first_line.backtrace_locations.first.lineno).not_to eq(at_second_line.backtrace_locations.first.lineno)
      expect(identities(at_first_line)[:v2]).to eq(identities(at_second_line)[:v2])
    end

    it "gives two v2 identities for two methods in one file" do
      first = capture { fixtures.first_method }
      second = capture { fixtures.second_method }

      expect(identities(first)[:v2]).not_to eq(identities(second)[:v2])
      expect(identities(first)[:v1]).to eq(identities(second)[:v1]) # rc.1 merged them
    end
  end

  describe "NameError#name (hardening-1-0-rc2/REQ-4)" do
    it "gives two v2 identities for two misspelled method names" do
      nme = capture { fixtures.send_to_nil(:nme) }
      emial = capture { fixtures.send_to_nil(:emial) }

      expect(described_class.normalize_message(nme.message)).to eq(described_class.normalize_message(emial.message))
      expect(identities(nme)[:v2]).not_to eq(identities(emial)[:v2])
    end

    it "replaces digits in the name, as in the message" do
      first = capture { fixtures.send_to_nil(:item_1) }
      second = capture { fixtures.send_to_nil(:item_22) }

      expect(identities(first)[:v2]).to eq(identities(second)[:v2])
    end
  end

  describe "a backtrace set from strings (hardening-1-0-rc2/REQ-1, REQ-2, REQ-3)" do
    it "gives the same v2 identity as the backtrace locations" do
      [
        capture { fixtures.two_lines(true) },
        capture { fixtures.load_user({}) },
        capture { fixtures.parse_a("x") },
        capture { fixtures.split_words("a 'b") },
        capture { fixtures.send_to_nil(:nme) }
      ].each do |error|
        copy = strings_only(error)
        expect(copy.backtrace_locations).to be_nil

        expect(identities(copy)[:v2]).to eq(identities(error)[:v2]), "for #{error.class}: #{error.message}"
      end
    end

    it "follows the same rules when backtrace_locations raises" do
      error = capture { fixtures.first_method }
      expected = identities(error)[:v2]
      allow(error).to receive(:backtrace_locations).and_raise(RuntimeError, "unexpected")

      expect(identities(error)[:v2]).to eq(expected)
    end
  end

  describe "custom_fingerprint (hardening-1-0-rc2/REQ-7)" do
    after { RailsErrorDashboard.reset_configuration! }

    it "returns rc.1's value as the custom identity, and no v2 or v1" do
      RailsErrorDashboard.configure do |config|
        config.custom_fingerprint = ->(exception, _context) { "custom:#{exception.class.name}" }
      end
      error = capture { fixtures.first_method }

      result = identities(error)

      expect(result[:custom]).to eq(described_class.call(error))
      expect(result[:custom]).to eq(Digest::SHA256.hexdigest("custom:ArgumentError")[0..15])
      expect(result[:v2]).to be_nil
      expect(result[:v1]).to be_nil
    end
  end
end
