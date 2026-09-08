# frozen_string_literal: true

module RailsErrorDashboard
  # Builds the dummy app's test database, from schema.rb or from the gem's
  # migrations. See the comment in spec/rails_helper.rb.
  module TestSchema
    GEM_MIGRATIONS = File.expand_path("../../db/migrate", __dir__)

    module_function

    def mode
      explicit = ENV["RED_TEST_SCHEMA"].to_s.strip
      return explicit.to_sym unless explicit.empty?

      sqlite? ? :schema : :migrations
    end

    def sqlite?
      ActiveRecord::Base.connection_db_config.adapter.to_s.start_with?("sqlite")
    end

    def build!
      case mode
      when :schema
        ActiveRecord::Tasks::DatabaseTasks.load_schema_current
      when :migrations
        migrate!
      else
        raise ArgumentError, "RED_TEST_SCHEMA must be 'schema' or 'migrations' (got #{ENV['RED_TEST_SCHEMA'].inspect})"
      end
    end

    # Run every gem migration that has not been applied. On a database where
    # they have all run this is a no-op, so repeated local runs are cheap; a
    # fresh database (CI) gets the full chain, squashed first migration
    # included.
    def migrate!
      was_verbose = ActiveRecord::Migration.verbose
      ActiveRecord::Migration.verbose = false
      migration_context.migrate
      # A backfill migration part-way through the chain queries the models,
      # which caches their columns as of THAT point; anything added by a later
      # migration (environment, the occurrence release fields) would then be
      # unknown to the model for the whole run.
      ActiveRecord::Base.connection.schema_cache.clear!
      ActiveRecord::Base.descendants.each(&:reset_column_information)
    ensure
      ActiveRecord::Migration.verbose = was_verbose
    end

    # Rails 7.0's SchemaMigration is a model class (responds to create_table)
    # and the context wants it passed in; from 7.1 it is instantiated per
    # connection and the context builds it itself.
    def migration_context
      if ActiveRecord::SchemaMigration.respond_to?(:create_table)
        ActiveRecord::MigrationContext.new([ GEM_MIGRATIONS ], ActiveRecord::SchemaMigration)
      else
        ActiveRecord::MigrationContext.new([ GEM_MIGRATIONS ])
      end
    end
  end
end
