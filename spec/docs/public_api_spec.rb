# frozen_string_literal: true

require "rails_helper"
require "prism"
require "rake"
require "rails/generators"

# docs/PUBLIC_API.md is what 1.x promises not to break, so it can't fall behind.
# Each group's fenced list is compared with the code, in both directions: a new
# option with no line fails here, and so does a line for one that's gone.
RSpec.describe "The public API page" do
  generators = Dir[RailsErrorDashboard::Engine.root.join("lib/generators/rails_error_dashboard/*/*_generator.rb")]
  generators.each { |file| require file }

  let(:root) { RailsErrorDashboard::Engine.root }
  let(:page) { root.join("docs/PUBLIC_API.md").read }

  def block(heading)
    page[/^#+ #{Regexp.escape(heading)}\n.*?```text\n(.*?)```/m, 1] || raise("no list under #{heading}")
  end

  # Each line as written, less its comment.
  def entries(heading)
    block(heading).lines.map { |line| line.split("#").first.strip }.reject(&:empty?)
  end

  def listed(heading)
    entries(heading).map { |entry| entry.split("(").first.strip }
  end

  def marked(heading, mark)
    block(heading).lines.grep(/# #{mark}/).map { |line| line.split("#").first.strip }
  end

  # The code, not its comments: a plugin's usage example once put four ENV names
  # on this page that RED never reads.
  def source(glob)
    Dir[root.join(glob)].flat_map { |file| File.readlines(file) }.grep_v(/\A\s*#/).join
  end

  def nodes_under(node)
    [ node, *node.compact_child_nodes.flat_map { |child| nodes_under(child) } ]
  end

  # Every key a method of the health query can answer with, in any branch.
  def health_keys(method_name)
    file = root.join("lib/rails_error_dashboard/queries/health_status.rb")
    definition = nodes_under(Prism.parse_file(file.to_s).value).find { |node| node.is_a?(Prism::DefNode) && node.name == method_name && node.receiver.nil? }
    nodes = nodes_under(definition)
    literal = nodes.grep(Prism::AssocNode).map(&:key).grep(Prism::SymbolNode).map(&:unescaped)
    assigned = nodes.grep(Prism::CallNode).select { |call| call.name == :[]= }.map { |call| call.arguments.arguments.first.unescaped }

    (literal + assigned).uniq
  end

  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("rails_error_dashboard:verify") }

  it "lists every config option, and no others (public-api-and-policies/REQ-3)" do
    options = RailsErrorDashboard::Configuration.public_instance_methods(false).grep(/=\z/).map { |name| name.to_s.chomp("=") }

    expect(listed("Configuration options")).to match_array(options)
  end

  it "gives every live config option a row in the configuration guide and its copy (public-api-and-policies/REQ-1)" do
    live = listed("Configuration options") - marked("Configuration options", "deprecated")

    %w[docs/guides/CONFIGURATION.md _guides/configuration.md].each do |guide|
      text = root.join(guide).read

      expect(live.reject { |option| text.match?(/^\| `#{option}` \|/) }).to be_empty
    end
  end

  it "lists every environment variable RED reads, and no others (public-api-and-policies/REQ-3)" do
    read = source("{app,config,db,lib}/**/*.{rb,rake,erb}").scan(/ENV(?:\.fetch\(|\.key\?\(|\[)\s*["']([A-Z0-9_]+)["']/).flatten

    # Rails' own, read to tell an asset build from a real boot.
    expect(listed("Environment variables")).to match_array(read.uniq - %w[SECRET_KEY_BASE_DUMMY])
  end

  it "lists every rake task, aliases included, and no others (public-api-and-policies/REQ-3)" do
    tasks = Rake::Task.tasks.map(&:name).grep(/\A(rails_)?error_dashboard:/)

    expect(listed("Rake tasks")).to match_array(tasks)
  end

  it "marks each deprecated name with the version that removes it (public-api-and-policies/REQ-1)" do
    aliases = Rake::Task.tasks.map(&:name).grep(/\Aerror_dashboard:/)

    expect(aliases.size).to eq(11)
    expect(page.scan(/^(\S+) +# deprecated, removed in 2\.0$/).flatten).to match_array(
      %w[async_adapter llm_observability_content_capture USE_SEPARATE_ERROR_DB] + aliases
    )
  end

  it "lists every generator (public-api-and-policies/REQ-1)" do
    names = generators.map { |file| "rails_error_dashboard:#{File.basename(file, '_generator.rb')}" }

    expect(listed("Generators")).to match_array(names)
  end

  generators.each do |file|
    name = File.basename(file, "_generator.rb")

    it "lists every option of the #{name} generator (public-api-and-policies/REQ-3)" do
      generator = RailsErrorDashboard::Generators.const_get("#{name.camelize}Generator")
      own = generator.class_options.keys - Rails::Generators::Base.class_options.keys

      expect(listed("#{name.capitalize} generator options")).to match_array(own.map { |option| "--#{option}" })
    end
  end

  it "lists every plugin hook and its arguments (public-api-and-policies/REQ-3)" do
    plugin = RailsErrorDashboard::Plugin
    hooks = plugin.public_instance_methods(false).grep(/\Aon_/).map do |hook|
      arguments = plugin.instance_method(hook).parameters.map(&:last)
      arguments.empty? ? hook.to_s : "#{hook}(#{arguments.join(', ')})"
    end

    expect(entries("Plugin hooks")).to match_array(hooks)
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

  it "lists every argument of ManualErrorReporter.report, and which are required (public-api-and-policies/REQ-1)" do
    parameters = RailsErrorDashboard::ManualErrorReporter.method(:report).parameters

    expect(listed("ManualErrorReporter.report")).to match_array(parameters.map { |_, name| name.to_s })
    expect(marked("ManualErrorReporter.report", "required")).to match_array(parameters.select { |kind, _| kind == :keyreq }.map { |_, name| name.to_s })
  end

  it "keeps the public URLs to exactly three (public-api-and-policies/REQ-1)" do
    expect(listed("URLs")).to contain_exactly("GET /health", "POST /webhooks/:provider", "GET /errors/:id")
  end

  it "freezes the health check's statuses (public-api-and-policies/REQ-1)" do
    query = RailsErrorDashboard::Queries::HealthStatus
    statuses = query.constants(false).map { |name| query.const_get(name) }.grep(String)

    expect(listed("Health check statuses")).to match_array(statuses)
    expect(statuses).to include("skipped")
  end

  it "freezes every field of the health check, in every branch (public-api-and-policies/REQ-1)" do
    checks = entries("Health checks").to_h { |line| line.split(": ").then { |name, fields| [ name, fields.split(", ") ] } }

    expect(checks.keys).to match_array(RailsErrorDashboard::Queries::HealthStatus.call[:checks].keys.map(&:to_s))
    expect(listed("Health check fields")).to match_array(health_keys(:call) - checks.keys)

    checks.each do |name, fields|
      expected = health_keys(:"check_#{name}")
      # Answered in place of check_errors when the database is down.
      expected |= health_keys(:skipped) if name == "errors"

      expect(fields).to match_array(expected)
    end
  end

  it "lists every OTel span, and no others (public-api-and-policies/REQ-1)" do
    spans = source("lib/**/*.rb").scan(/Tracer\s*\.in_span\(\s*"([a-z_]+)"/).flatten.uniq

    expect(listed("OpenTelemetry spans")).to match_array(spans.map { |span| "rails_error_dashboard.#{span}" })
  end

  it "lists every OTel attribute, and no others (public-api-and-policies/REQ-1)" do
    code = source("lib/**/*.rb")
    attributes = code.scan(/set_attribute\("([a-z_.]+)"/).flatten + code.scan(/"((?:error|rails_error_dashboard)\.[a-z_.]+)" =>/).flatten

    expect(listed("OpenTelemetry attributes")).to match_array(attributes.uniq)
  end

  it "says what's private (public-api-and-policies/REQ-2)" do
    private_part = page[/^## What's private.*\z/m].to_s

    expect(private_part).to include(
      "Database tables, columns and models", "Job classes and their arguments", "Classes and modules not named on this page",
      "i18n keys", "HTML, CSS and JavaScript", "Every dashboard URL not listed"
    )
  end

  it "links the pages with the details (public-api-and-policies/REQ-1)" do
    expect(page).to include("guides/CONFIGURATION.md", "API_REFERENCE.md", "WEBHOOKS.md", "PLUGIN_SYSTEM.md", "VERSIONING.md")
  end
end
