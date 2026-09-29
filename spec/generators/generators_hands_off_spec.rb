# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "digest"
require "generators/rails_error_dashboard/install/install_generator"
require "generators/rails_error_dashboard/uninstall/uninstall_generator"
require "generators/rails_error_dashboard/solid_queue/solid_queue_generator"

# RED never writes another gem's files (decision 0001). Its old Solid Queue
# generator overwrote config/queue.yml with a file that started no dispatcher,
# so no delayed job ran in the host app. Every RED generator, run the way a
# user runs it, may change only RED's own files: its initializer, its
# migrations and its line in config/routes.rb.
RSpec.describe "RED's generators and the app's other files", type: :generator do
  include FileUtils

  let(:root) { File.expand_path("../../tmp/hands_off_test", __dir__) }
  let(:fixtures) { File.expand_path("../fixtures/solid_queue", __dir__) }

  # A Rails 8 app with Solid Queue set up, as `rails new` and
  # `solid_queue:install` leave it, plus one migration of the app's own.
  let(:app_files) do
    {
      "Gemfile" => "source \"https://rubygems.org\"\ngem \"rails\"\ngem \"solid_queue\"\n",
      "bin/jobs" => "#!/usr/bin/env ruby\n\nrequire_relative \"../config/environment\"\n" \
                    "require \"solid_queue/cli\"\n\nSolidQueue::Cli.start(ARGV)\n",
      "config/application.rb" => "module HostApp\n  class Application < Rails::Application\n  end\nend\n",
      "config/database.yml" => "production:\n  primary:\n    adapter: sqlite3\n    database: storage/production.sqlite3\n" \
                               "  queue:\n    adapter: sqlite3\n    database: storage/production_queue.sqlite3\n" \
                               "    migrations_paths: db/queue_migrate\n",
      "config/environments/development.rb" => "Rails.application.configure do\nend\n",
      "config/environments/production.rb" => "Rails.application.configure do\n" \
                                             "  config.active_job.queue_adapter = :solid_queue\n" \
                                             "  config.solid_queue.connects_to = { database: { writing: :queue } }\nend\n",
      "config/puma.rb" => "plugin :solid_queue if ENV[\"SOLID_QUEUE_IN_PUMA\"]\n",
      "config/queue.yml" => File.read(File.join(fixtures, "solid_queue_install_queue.yml")),
      "config/recurring.yml" => "production:\n  clear_solid_queue_finished_jobs:\n" \
                                "    command: \"SolidQueue::Job.clear_finished_in_batches\"\n" \
                                "    schedule: every hour at minute 12\n",
      "config/routes.rb" => "Rails.application.routes.draw do\nend\n",
      "db/migrate/20260101000000_create_widgets.rb" => "class CreateWidgets < ActiveRecord::Migration[8.1]\nend\n",
      "db/queue_schema.rb" => "ActiveRecord::Schema[8.1].define(version: 1) do\nend\n"
    }
  end

  before do
    app_files.each do |path, content|
      mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), content)
    end
    allow($stdin).to receive(:tty?).and_return(false)
  end

  after { rm_rf(root) }

  def red_owned?(path)
    path == "config/initializers/rails_error_dashboard.rb" ||
      path == "config/routes.rb" ||
      path.match?(%r{\Adb/(migrate|error_dashboard_migrate)/\d+_\w*\.rails_error_dashboard\.rb\z})
  end

  # Every file outside RED's own, with a digest of its bytes.
  def other_files
    Dir.glob("**/*", File::FNM_DOTMATCH, base: root)
      .select { |path| File.file?(File.join(root, path)) }
      .reject { |path| red_owned?(path) }
      .sort
      .to_h { |path| [ path, Digest::SHA256.file(File.join(root, path)).hexdigest ] }
  end

  def quietly
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  def install(**options)
    generator = RailsErrorDashboard::Generators::InstallGenerator.new([], { interactive: false }.merge(options), destination_root: root)
    generator.options = generator.options.merge(force: true)
    quietly { generator.invoke_all }
  end

  def uninstall
    generator = RailsErrorDashboard::Generators::UninstallGenerator.new(
      [], { keep_data: true, skip_confirmation: true }, destination_root: root
    )
    # The uninstall generator looks for files relative to the app root.
    Dir.chdir(root) { quietly { generator.invoke_all } }
  end

  def solid_queue_generator
    generator = RailsErrorDashboard::Generators::SolidQueueGenerator.new([], { force: true }, destination_root: root)
    quietly { generator.invoke_all }
  end

  def red_migrations
    Dir.glob("db/{migrate,error_dashboard_migrate}/*.rails_error_dashboard.rb", base: root)
  end

  it "installs, re-installs, checks Solid Queue and uninstalls without changing any other file" do
    before = other_files

    install
    expect(red_migrations).not_to be_empty
    expect(other_files).to eq(before)

    install
    expect(other_files).to eq(before)

    solid_queue_generator
    expect(other_files).to eq(before)

    uninstall
    expect(red_migrations).to be_empty
    expect(File.exist?(File.join(root, "config/initializers/rails_error_dashboard.rb"))).to be false
    expect(other_files).to eq(before)
  end

  it "installs with a separate database without changing any other file" do
    before = other_files

    install(separate_database: true, database: "error_dashboard")

    expect(Dir.glob("db/error_dashboard_migrate/*.rails_error_dashboard.rb", base: root)).not_to be_empty
    expect(other_files).to eq(before)
  end
end
