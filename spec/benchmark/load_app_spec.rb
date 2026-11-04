# frozen_string_literal: true

require "rails_helper"
require "yaml"

# The app's Puma, database and job settings are the generator's, so they aren't
# in this repo to read. These examples hold the things that could move them: the
# Rails version that writes them, and anything of ours that might override them.
# Booting the app shows the values themselves.
RSpec.describe "the load test's app" do
  load_folder = File.expand_path("../../benchmark/load", __dir__)

  let(:dockerfile) { File.read(File.join(load_folder, "Dockerfile")) }
  let(:template) { File.read(File.join(load_folder, "app/template.rb")) }
  let(:compose) { YAML.load_file(File.join(load_folder, "compose.yml")) }
  let(:app_settings) { compose.dig("services", "app", "environment") }
  let(:our_files) { [ dockerfile, template, compose.to_yaml ] }

  it "runs in production mode (deploy-shape-benchmark/REQ-8)" do
    expect(dockerfile).to match(/^ENV RAILS_ENV="production"/)
    expect(app_settings).not_to have_key("RAILS_ENV")
  end

  it "serves through Puma, behind the proxy the generator puts in front of it (deploy-shape-benchmark/REQ-8)" do
    expect(dockerfile).to include('CMD ["./bin/thrust", "./bin/rails", "server"]')
    expect(template).not_to include("config/puma.rb")
  end

  it "loads jemalloc as the generator's Dockerfile does (deploy-shape-benchmark/REQ-8)" do
    expect(dockerfile).to include("libjemalloc2", 'LD_PRELOAD="/usr/local/lib/libjemalloc.so"')
  end

  it "leaves Puma on one process and 3 threads (deploy-shape-benchmark/REQ-8)" do
    expect(dockerfile).to match(/^ARG RAILS_VERSION=8\.1\.4$/)
    our_files.each { |file| expect(file).not_to include("WEB_CONCURRENCY", "RAILS_MAX_THREADS") }
  end

  it "takes everything from the generator but the database (deploy-shape-benchmark/REQ-8)" do
    expect(dockerfile).to include("rails new . --name=shop --database=postgresql --template=/template.rb\n")
  end

  it "adds RED with its installer, not by hand (deploy-shape-benchmark/REQ-8)" do
    expect(template).to include('generate "rails_error_dashboard:install", "--no-interactive"')
    expect(template).not_to include("config/initializers", "RailsErrorDashboard.configure")
  end

  it "leaves the job queue on the generator's Solid Queue, inside Puma as its deploy file does (deploy-shape-benchmark/REQ-8)" do
    expect(template).not_to include("queue_adapter", "config/queue.yml")
    expect(app_settings).to include("SOLID_QUEUE_IN_PUMA" => "true")
  end

  it "leaves the database settings as generated (deploy-shape-benchmark/REQ-8)" do
    expect(template).not_to include("config/database.yml")
    expect(app_settings.keys.grep(/DATABASE_URL/)).to be_empty
  end

  it "fails a request 60 frames down, as bin/benchmark does (deploy-shape-benchmark/REQ-8)" do
    expect(template).to match(/FRAMES = 60$/)
  end
end
