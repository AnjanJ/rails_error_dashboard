# frozen_string_literal: true

require "rails_helper"
require "rake"
require "rails/generators"
require "generators/rails_error_dashboard/install/install_generator"

# docs/PUBLIC_API.md is what 1.x promises not to break, so it can't fall behind.
# Each group's fenced list is compared with the code, in both directions: a new
# option with no line fails here, and so does a line for one that's gone.
RSpec.describe "The public API page" do
  root = RailsErrorDashboard::Engine.root
  let(:page) { root.join("docs/PUBLIC_API.md").read }

  def listed(heading)
    block = page[/^#+ #{Regexp.escape(heading)}\n.*?```text\n(.*?)```/m, 1]
    raise "no list under #{heading}" unless block

    block.lines.map { |line| line.split("#").first.split("(").first.strip }.reject(&:empty?)
  end

  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("rails_error_dashboard:verify") }

  it "lists every config option, and no others (public-api-and-policies/REQ-3)" do
    options = RailsErrorDashboard::Configuration.public_instance_methods(false).grep(/=\z/).map { |name| name.to_s.chomp("=") }

    expect(listed("Configuration options")).to match_array(options)
  end

  it "documents every live config option in the configuration guide (public-api-and-policies/REQ-1)" do
    guide = root.join("docs/guides/CONFIGURATION.md").read
    options = listed("Configuration options") - %w[async_adapter llm_observability_content_capture]

    expect(options.reject { |option| guide.include?("`#{option}`") }).to be_empty
  end

  it "lists every environment variable RED reads, and no others (public-api-and-policies/REQ-3)" do
    read = Dir[root.join("lib/**/*.rb")].flat_map { |file| File.read(file).scan(/ENV(?:\.fetch\(|\.key\?\(|\[)\s*["']([A-Z0-9_]+)["']/).flatten }

    # Rails' own, read to tell an asset build from a real boot.
    expect(listed("Environment variables")).to match_array(read.uniq - %w[SECRET_KEY_BASE_DUMMY])
  end

  it "lists every rake task, aliases included, and no others (public-api-and-policies/REQ-3)" do
    tasks = Rake::Task.tasks.map(&:name).grep(/\A(rails_)?error_dashboard:/)

    expect(listed("Rake tasks")).to match_array(tasks)
  end

  it "marks each deprecated name with the version that removes it (public-api-and-policies/REQ-1)" do
    deprecated = %w[async_adapter llm_observability_content_capture USE_SEPARATE_ERROR_DB error_dashboard:verify]

    deprecated.each { |name| expect(page).to match(/^#{Regexp.escape(name)} +# deprecated, removed in 2\.0$/) }
  end

  it "lists every option of the install generator (public-api-and-policies/REQ-3)" do
    generator = RailsErrorDashboard::Generators::InstallGenerator
    own = generator.class_options.keys - Rails::Generators::Base.class_options.keys

    expect(listed("Install generator options")).to match_array(own.map { |name| "--#{name}" })
  end

  it "lists both generators (public-api-and-policies/REQ-1)" do
    expect(listed("Generators")).to contain_exactly("rails_error_dashboard:install", "rails_error_dashboard:uninstall")
  end

  it "lists every plugin hook (public-api-and-policies/REQ-3)" do
    hooks = RailsErrorDashboard::Plugin.public_instance_methods(false).grep(/\Aon_/).map(&:to_s)

    expect(listed("Plugin hooks")).to match_array(hooks)
    expect(hooks.size).to eq(12)
  end

  it "lists every module method (public-api-and-policies/REQ-3)" do
    methods = RailsErrorDashboard.singleton_methods(false).map(&:to_s)
    # reset_* are for tests. The rest are what an isolated engine defines for itself.
    private_ones = %w[
      reset_configuration! reset_detected_git_sha! railtie_helpers_paths railtie_namespace
      railtie_routes_url_helpers table_name_prefix use_relative_model_naming?
    ]

    expect(listed("Module methods")).to match_array(methods - private_ones)
  end

  it "lists every argument of ManualErrorReporter.report (public-api-and-policies/REQ-1)" do
    arguments = RailsErrorDashboard::ManualErrorReporter.method(:report).parameters.map(&:last).map(&:to_s)

    expect(listed("ManualErrorReporter.report")).to match_array(arguments)
  end

  it "keeps the public URLs to exactly three (public-api-and-policies/REQ-1)" do
    expect(listed("URLs")).to contain_exactly("GET /health", "POST /webhooks/:provider", "GET /errors/:id")
  end

  it "freezes the health check's fields and statuses (public-api-and-policies/REQ-1)" do
    health = RailsErrorDashboard::Queries::HealthStatus.call
    statuses = RailsErrorDashboard::Queries::HealthStatus.constants(false)
      .map { |name| RailsErrorDashboard::Queries::HealthStatus.const_get(name) }.grep(String)

    expect(listed("Health check fields")).to include(*health.keys.map(&:to_s), *health[:checks].keys.map(&:to_s))
    expect(listed("Health check statuses")).to match_array(statuses)
    expect(statuses).to include("skipped")
  end

  it "lists OTel spans and attributes that exist (public-api-and-policies/REQ-1)" do
    code = Dir[root.join("lib/**/*.rb")].map { |file| File.read(file) }.join

    listed("OpenTelemetry spans").each { |span| expect(code).to include(%("#{span.delete_prefix('rails_error_dashboard.')}")) }
    listed("OpenTelemetry attributes").each { |attribute| expect(code).to include(%("#{attribute}")) }
  end

  it "says what's private (public-api-and-policies/REQ-2)" do
    private_part = page[/^## What's private.*\z/m].to_s

    expect(private_part).to include("Database tables", "Job classes", "i18n keys", "HTML, CSS and JavaScript", "dashboard URL")
  end

  it "links the pages with the details (public-api-and-policies/REQ-1)" do
    expect(page).to include("guides/CONFIGURATION.md", "API_REFERENCE.md", "WEBHOOKS.md", "PLUGIN_SYSTEM.md", "VERSIONING.md")
  end
end
