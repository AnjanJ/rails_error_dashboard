# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/rails_error_dashboard/solid_queue/solid_queue_generator"

# The generator used to write a config/queue.yml with workers and no
# dispatchers, which made Solid Queue start no dispatcher at all: no delayed
# job ran, the host app's own included. It is retired: it writes nothing and
# checks whatever config the app already has.
RSpec.describe RailsErrorDashboard::Generators::SolidQueueGenerator, type: :generator do
  include FileUtils

  let(:destination_root) { File.expand_path("../../tmp/solid_queue_generator_test", __dir__) }
  let(:fixtures) { File.expand_path("../fixtures/solid_queue", __dir__) }
  let(:queue_yml) { File.join(destination_root, "config/queue.yml") }

  before do
    mkdir_p("#{destination_root}/config/environments")
    %w[development test production].each do |env|
      File.write("#{destination_root}/config/environments/#{env}.rb", "")
    end
  end

  after do
    rm_rf(destination_root)
  end

  def run_generator(force: false)
    generator = described_class.new([], { force: force }, destination_root: destination_root)
    capture_stdout { generator.invoke_all }
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  it "does not create config/queue.yml" do
    run_generator

    expect(File.exist?(queue_yml)).to be false
  end

  it "says it is deprecated and that Solid Queue's own config covers RED's queues" do
    output = run_generator

    expect(output).to include("deprecated")
    expect(output).to include("solid_queue:install")
    expect(output).to include("bin/jobs")
  end

  it "points to Solid Queue's installer when the app has no config" do
    output = run_generator

    expect(output).to include("No config/queue.yml")
  end

  context "with the config the old generator wrote" do
    before { cp(File.join(fixtures, "red_generator_queue.yml"), queue_yml) }

    it "leaves the file untouched, even with --force" do
      before_bytes = File.binread(queue_yml)

      run_generator(force: true)

      expect(File.binread(queue_yml)).to eq(before_bytes)
    end

    it "reports the missing dispatcher for every environment the app has" do
      output = run_generator

      %w[development test production].each do |env|
        expect(output).to match(/#{env}:.*no dispatcher/)
      end
      expect(output).to include("Solid Queue's own template")
    end
  end

  context "with Solid Queue's own config" do
    before { cp(File.join(fixtures, "solid_queue_install_queue.yml"), queue_yml) }

    # The old generator replaced this working file with its broken one.
    it "leaves the file untouched, even with --force" do
      before_bytes = File.binread(queue_yml)

      run_generator(force: true)

      expect(File.binread(queue_yml)).to eq(before_bytes)
    end

    it "reports nothing wrong" do
      output = run_generator

      expect(output).not_to include("no dispatcher")
      expect(output).to include("processes RED's queues")
    end
  end
end
