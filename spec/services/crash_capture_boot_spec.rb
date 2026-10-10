# frozen_string_literal: true

require "rails_helper"
require "zeitwerk"

# Boot-phase crashes: a Zeitwerk::NameError from eager loading, a SyntaxError
# in a model, an initializer that raised. They kill the process before
# config.after_initialize runs, so the at_exit hook has to be registered
# earlier (see the engine initializer) and the import has to mark them apart
# from runtime crashes.
RSpec.describe RailsErrorDashboard::Services::CrashCapture, "boot crashes" do
  let(:crash_dir) { Dir.mktmpdir("red_boot_crash") }

  before do
    described_class.reset!
    RailsErrorDashboard.configuration.crash_capture_path = crash_dir
    described_class.enable!
  end

  after do
    described_class.reset!
    RailsErrorDashboard.reset_configuration!
    FileUtils.rm_rf(crash_dir)
  end

  def crash_file
    Dir.glob(File.join(crash_dir, "red_crash_*.json")).first
  end

  def captured
    JSON.parse(File.read(crash_file))
  end

  # A genuine Zeitwerk::NameError: a loader over a temp dir whose one file
  # defines the wrong constant.
  def real_zeitwerk_error
    dir = Dir.mktmpdir("red_zeitwerk")
    File.write(File.join(dir, "zeitwerk_bad.rb"), "class ZeitwerkWrongName; end\n")
    loader = Zeitwerk::Loader.new
    loader.push_dir(dir)
    loader.setup
    loader.eager_load
    raise "expected Zeitwerk::NameError"
  rescue Zeitwerk::NameError => e
    e
  ensure
    loader&.unload rescue nil
    Object.send(:remove_const, :ZeitwerkWrongName) if Object.const_defined?(:ZeitwerkWrongName)
    FileUtils.rm_rf(dir) if dir
  end

  describe "the phase marker" do
    it "marks a crash after initialize! finished as runtime" do
      described_class.capture!(RuntimeError.new("late"))

      expect(captured["phase"]).to eq("runtime")
      expect(captured).not_to have_key("boot")
    end

    it "marks a crash while the application is still initializing as boot" do
      allow(Rails.application).to receive(:initialized?).and_return(false)

      described_class.capture!(RuntimeError.new("early"))

      expect(captured["phase"]).to eq("boot")
    end
  end

  describe "the boot detail" do
    before { allow(Rails.application).to receive(:initialized?).and_return(false) }

    it "names the file and the constant for a real Zeitwerk::NameError" do
      error = real_zeitwerk_error
      expect(error.message).to match(/expected file .*zeitwerk_bad\.rb to define constant ZeitwerkBad/)

      described_class.capture!(error)

      expect(captured["exception_class"]).to eq("Zeitwerk::NameError")
      expect(captured["boot"]["constant"]).to eq("ZeitwerkBad")
      expect(captured["boot"]["file"]).to end_with("zeitwerk_bad.rb")
    end

    it "makes the file relative to Rails.root" do
      error = Zeitwerk::NameError.new(
        "expected file #{Rails.root}/app/models/widget.rb to define constant Widget, but didn't", :Widget
      )

      described_class.capture!(error)

      expect(captured["boot"]).to eq("file" => "app/models/widget.rb", "constant" => "Widget")
    end

    it "names the first app frame for any other boot crash" do
      error = NoMethodError.new("undefined method 'has_many_things' for class Widget")
      error.set_backtrace([
        "/gems/activerecord/lib/x.rb:1:in `y'",
        "#{Rails.root}/app/models/widget.rb:4:in `<class:Widget>'",
        "#{Rails.root}/config/environment.rb:5:in `<main>'"
      ])

      described_class.capture!(error)

      expect(captured["boot"]).to eq("file" => "app/models/widget.rb:4")
    end

    it "leaves the detail empty when nothing points at the app" do
      error = RuntimeError.new("boom")
      error.set_backtrace([ "/gems/railties/lib/rails/application.rb:1:in `initialize!'" ])

      described_class.capture!(error)

      expect(captured["boot"]).to eq({})
    end
  end

  describe "import" do
    def write(data)
      File.write(File.join(crash_dir, "red_crash_#{data[:pid]}.json"), JSON.generate(data))
    end

    let(:boot_data) do
      {
        exception_class: "Zeitwerk::NameError",
        message: "expected file app/models/widget.rb to define constant Widget, but didn't",
        backtrace: [ "/gems/zeitwerk/lib/zeitwerk/loader/callbacks.rb:30:in `on_file_autoloaded'" ],
        timestamp: Time.now.utc.iso8601, pid: 4242, ruby_version: RUBY_VERSION,
        phase: "boot", boot: { file: "app/models/widget.rb", constant: "Widget" }
      }
    end

    it "imports a boot crash with its own platform and the boot detail" do
      write(boot_data)

      described_class.import!

      row = RailsErrorDashboard::ErrorLog.last
      expect(row.platform).to eq("boot_crash")
      expect(row.error_type).to eq("Zeitwerk::NameError")
      expect(row.severity.to_s).to eq("critical")
      info = JSON.parse(row.environment_info)
      expect(info["phase"]).to eq("boot")
      expect(info["boot"]).to eq("file" => "app/models/widget.rb", "constant" => "Widget")
      expect(crash_file).to be_nil
    end

    it "keeps a runtime crash on the crash_capture platform" do
      write(boot_data.merge(phase: "runtime", boot: nil, exception_class: "RuntimeError", message: "late"))

      described_class.import!

      expect(RailsErrorDashboard::ErrorLog.last.platform).to eq("crash_capture")
    end

    it "counts the same crash on the next restart on the same row instead of failing the import" do
      write(boot_data)
      described_class.import!
      write(boot_data.merge(pid: 4243, timestamp: 1.minute.from_now.utc.iso8601))

      expect { described_class.import! }.not_to change(RailsErrorDashboard::ErrorLog, :count)

      expect(RailsErrorDashboard::ErrorLog.last.occurrence_count).to eq(2)
      expect(Dir.glob(File.join(crash_dir, "*.failed"))).to be_empty
    end
  end
end
