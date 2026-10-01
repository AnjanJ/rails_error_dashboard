# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/rails_error_dashboard/uninstall/uninstall_generator"

RSpec.describe RailsErrorDashboard::Generators::UninstallGenerator, type: :generator do
  describe "uninstall generator" do
    it "exists and is loadable" do
      expect(described_class).to be_a(Class)
      expect(described_class.ancestors).to include(Rails::Generators::Base)
    end

    it "has correct class options" do
      expect(described_class.class_options.keys).to include(:keep_data)
      expect(described_class.class_options.keys).to include(:skip_confirmation)
      expect(described_class.class_options.keys).to include(:manual_only)
    end

    it "has all required methods" do
      generator = described_class.new
      expect(generator).to respond_to(:welcome_message)
      expect(generator).to respond_to(:detect_installed_components)
      expect(generator).to respond_to(:show_manual_instructions)
      expect(generator).to respond_to(:remove_initializer)
      expect(generator).to respond_to(:remove_route)
      expect(generator).to respond_to(:remove_migrations)
      expect(generator).to respond_to(:drop_database_tables)
    end
  end

  describe "component detection helpers" do
    let(:generator) { described_class.new }

    describe "#route_mounted?" do
      it "returns false when routes.rb doesn't exist" do
        allow(File).to receive(:exist?).with("config/routes.rb").and_return(false)
        expect(generator.send(:route_mounted?)).to be false
      end

      it "returns true when RailsErrorDashboard::Engine is mounted" do
        allow(File).to receive(:exist?).with("config/routes.rb").and_return(true)
        allow(File).to receive(:read).with("config/routes.rb").and_return(
          "mount RailsErrorDashboard::Engine => '/error_dashboard'"
        )
        expect(generator.send(:route_mounted?)).to be true
      end
    end

    describe "#migrations_exist?" do
      it "returns true when migration files exist" do
        allow(Dir).to receive(:glob).with(described_class::MIGRATION_GLOBS).and_return(
          [ "db/migrate/20251224_create_rails_error_dashboard_error_logs.rb" ]
        )
        expect(generator.send(:migrations_exist?)).to be true
      end

      it "returns false when no migration files exist" do
        allow(Dir).to receive(:glob).with(described_class::MIGRATION_GLOBS).and_return([])
        expect(generator.send(:migrations_exist?)).to be false
      end
    end

    describe "#gemfile_includes_gem?" do
      it "returns true when gem is in Gemfile" do
        allow(File).to receive(:exist?).with("Gemfile").and_return(true)
        allow(File).to receive(:read).with("Gemfile").and_return("gem 'rails_error_dashboard'")
        expect(generator.send(:gemfile_includes_gem?)).to be true
      end

      it "returns false when gem is not in Gemfile" do
        allow(File).to receive(:exist?).with("Gemfile").and_return(true)
        allow(File).to receive(:read).with("Gemfile").and_return("gem 'rails'")
        expect(generator.send(:gemfile_includes_gem?)).to be false
      end
    end
  end

  describe "table names" do
    let(:generator) { described_class.new }

    # The generator used to know 5 of the 13 tables.
    it "lists every RED table on the error database" do
      expect(generator.send(:table_names)).to match_array(red_tables)
    end

    it "shows why, and lists nothing, when the error database can't be reached" do
      allow(RailsErrorDashboard::Commands::DropAllTables).to receive(:connection)
        .and_raise(RailsErrorDashboard::Commands::DropAllTables::Error, "no 'error_dashboard' entry")

      output = capture_stdout { expect(generator.send(:table_names)).to eq([]) }

      expect(output).to include("no 'error_dashboard' entry")
    end
  end

  # With use_separate_database on but no database.yml entry for it (or the
  # database server down), the generator could not see the tables, treated that
  # as "no tables", and removed the initializer, route and migrations anyway.
  # The error database kept every table, and with the initializer gone nothing
  # could find them again. Found by the release scenario run for 0.14.3.
  describe "when the error database can't be reached" do
    before do
      allow(RailsErrorDashboard::Commands::DropAllTables).to receive(:connection)
        .and_raise(RailsErrorDashboard::Commands::DropAllTables::Error, "no 'error_dashboard' entry")
    end

    it "stops before anything is removed" do
      generator = described_class.new([], { skip_confirmation: true }, {})

      expect { capture_stdout { generator.detect_installed_components } }
        .to raise_error(Thor::Error, /nothing was removed.*no 'error_dashboard' entry/m)
    end

    it "carries on with --keep-data, which removes only files" do
      generator = described_class.new([], { keep_data: true, skip_confirmation: true }, {})

      expect { capture_stdout { generator.detect_installed_components } }.not_to raise_error
    end

    it "carries on with --manual-only, which removes nothing" do
      generator = described_class.new([], { manual_only: true }, {})

      expect { capture_stdout { generator.detect_installed_components } }.not_to raise_error
    end
  end

  describe "dropping the tables" do
    let(:generator) { described_class.new([], {}, {}) }

    before { generator.instance_variable_set(:@components, { tables: true }) }

    # Thor runs a generator's public methods in the order they are defined.
    it "drops the tables before it removes any file" do
      order = described_class.all_commands.keys

      %w[remove_initializer remove_route remove_migrations].each do |removal|
        expect(order.index("drop_database_tables")).to be < order.index(removal)
      end
    end

    it "drops through DropAllTables on the error database" do
      connection = RailsErrorDashboard::ErrorLogsRecord.connection
      allow(RailsErrorDashboard::Commands::DropAllTables).to receive(:call).and_return(%w[a b])

      capture_stdout { generator.drop_database_tables }

      expect(RailsErrorDashboard::Commands::DropAllTables).to have_received(:call).with(connection: connection)
    end

    it "stops the uninstall when the drop fails, instead of reporting success" do
      allow(RailsErrorDashboard::Commands::DropAllTables).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "FOREIGN KEY constraint failed")

      expect { capture_stdout { generator.drop_database_tables } }
        .to raise_error(Thor::Error, /no files were removed.*FOREIGN KEY/)
    end
  end

  # The completion message left out two steps its own manual instructions list.
  describe "completion message" do
    it "lists the schema dump and the database.yml entry" do
      output = capture_stdout { described_class.new([], {}).show_completion_message }

      expect(output).to include("bin/rails db:schema:dump", "config/database.yml")
    end

    it "skips the schema dump when the tables were kept" do
      output = capture_stdout { described_class.new([], { keep_data: true }).show_completion_message }

      expect(output).not_to include("db:schema:dump")
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
