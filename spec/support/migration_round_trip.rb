# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "uri"

module RailsErrorDashboard
  # Runs gem migrations down and up on a scratch database, along the two
  # histories real installs have:
  #
  #   upgrade  every migration in order, without the complete schema
  #   fresh    the complete schema, then every migration
  #
  # In its own process, where ActiveRecord::Base IS the scratch database: several
  # migrations reach for ActiveRecord::Base or RED's models, and in the suite's
  # process those are the suite's database.
  #
  # Each history is walked once, and a migration goes down and up while it is the
  # newest, which is the state an in-order rollback meets. A round trip that
  # doesn't restore the schema rebuilds it, so it can't affect the next migration.
  module MigrationRoundTrip
    COMPLETE_SCHEMA = 20251223000000
    HISTORIES = %w[upgrade fresh].freeze

    module_function

    # @param versions [Array<Integer>] the migrations to round-trip
    # @return [Hash] history => version => what each step did, see Runner#round_trip
    def run(versions)
      Dir.mktmpdir("red_round_trip") do |dir|
        output = File.join(dir, "results.json")
        env = { "RAILS_ENV" => "test", "DATABASE_URL" => scratch_url(dir), "RED_TEST_SCHEMA" => nil }
        out, status = Open3.capture2e(env, Gem.ruby, __FILE__, output, *versions.map(&:to_s))
        raise "the round trip failed to run:\n#{out}" unless status.success?

        JSON.parse(File.read(output))
      end
    end

    def scratch_url(dir)
      return "sqlite3:#{File.join(dir, 'scratch.sqlite3')}" if TestSchema.sqlite?

      URI(ENV.fetch("DATABASE_URL")).tap { |url| url.path = "/red_round_trip_#{Process.pid}" }.to_s
    end

    class Runner
      IGNORED_TABLES = %w[schema_migrations ar_internal_metadata].freeze

      def initialize(versions)
        @versions = versions
        @added = {}
      end

      def call
        ActiveRecord::Migration.verbose = false
        @config = ActiveRecord::Base.connection_db_config
        @walks_end_clean = {}
        results = HISTORIES.to_h { |history| [ history, walk(history) ] }
        results.merge(
          "walks_end_clean" => @walks_end_clean,
          "empty" => down_on_an_empty_database,
          "complete_schema" => complete_schema_down
        )
      ensure
        ActiveRecord::Base.connection_pool.disconnect!
        ActiveRecord::Tasks::DatabaseTasks.drop(@config)
      end

      private

      def walk(history)
        results = {}
        rebuild(history)

        migrations(history).each do |migration|
          chosen = @versions.include?(migration.version)
          before = schema if chosen && !@added.key?(migration.version)
          migrate(:up, migration)
          next unless chosen

          after = schema
          @added[migration.version] ||= objects(after) - objects(before)
          # Limited to what's here: the first migrations add columns that later
          # ones remove, and that the complete schema never had.
          trip = round_trip(migration, @added[migration.version] & objects(after), after)
          results[migration.version.to_s] = trip
          rebuild(history, through: migration.version) unless trip["restored"]
        end

        walked = schema
        rebuild(history, through: migrations(history).last.version)
        @walks_end_clean[history] = schema == walked
        results
      end

      # object: what this migration adds, taken from the upgrade history, because
      # on the fresh history the complete schema has already added it.
      def round_trip(migration, object, after)
        down_error = attempt { migrate(:down, migration) }
        after_down = schema
        version_kept = migrated?(migration.version)
        down_again_error = attempt { migration.migrate(:down) }
        down_again_changed = schema != after_down
        up_error = attempt { migrate(:up, migration) }
        after_up = schema
        up_again_error = attempt { migration.migrate(:up) }
        ended = schema

        {
          "object" => object,
          "down" => { "error" => down_error, "version_kept" => version_kept, "left" => object & objects(after_down) },
          "down_again" => { "error" => down_again_error, "changed" => down_again_changed },
          "up" => { "error" => up_error, "missing" => object - objects(after_up) },
          "up_again" => { "error" => up_again_error, "changed" => ended != after_up },
          "restored" => ended == after
        }
      end

      # The far end of "its object doesn't exist": no table either, which the
      # walk never reaches. column_exists? raises there on all three databases.
      def down_on_an_empty_database
        rebuild("fresh")
        chosen = migrations("fresh").select { |migration| @versions.include?(migration.version) }
        chosen.to_h { |migration| [ migration.version.to_s, attempt { migration.migrate(:down) } ] }
      end

      def complete_schema_down
        rebuild("fresh", through: COMPLETE_SCHEMA)
        tables = schema.keys
        error = attempt { context.run(:down, COMPLETE_SCHEMA) }
        { "error" => error, "dropped" => tables - schema.keys, "left" => schema.keys }
      end

      def attempt
        yield
        nil
      rescue StandardError => e
        "#{e.class}: #{e.message}"
      end

      def rebuild(history, through: nil)
        ActiveRecord::Base.connection_pool.disconnect!
        ActiveRecord::Tasks::DatabaseTasks.drop(@config) if built?
        ActiveRecord::Tasks::DatabaseTasks.create(@config)
        ActiveRecord::Base.establish_connection(@config)
        @built = true
        # A backfill queries the models, which cache the columns they found.
        ActiveRecord::Base.descendants.each(&:reset_column_information)

        migrations(history).each { |migration| migrate(:up, migration) if through && migration.version <= through }
      end

      def built?
        @built
      end

      def migrations(history)
        all = context.migrations
        history == "upgrade" ? all.reject { |migration| migration.version == COMPLETE_SCHEMA } : all
      end

      # Through the migrator, as db:migrate:down does: it wraps the migration in a
      # transaction where the database can, and records the version.
      def migrate(direction, migration)
        context.run(direction, migration.version)
      end

      def migrated?(version)
        context.get_all_versions.include?(version)
      end

      def context
        TestSchema.migration_context
      end

      def schema
        connection = ActiveRecord::Base.connection
        (connection.tables - IGNORED_TABLES).sort.to_h do |table|
          [ table, {
            columns: connection.columns(table).map { |c| [ c.name, c.sql_type, c.null, c.default ] }.sort_by(&:first),
            indexes: connection.indexes(table).map { |i| [ i.name, i.columns, i.unique, i.where ] }.sort_by(&:first),
            foreign_keys: connection.foreign_keys(table).map { |k| [ k.column, k.to_table ] }.sort
          } ]
        end
      end

      # The schema as a flat list, so that what a migration adds is a difference.
      def objects(schema)
        schema.flat_map do |table, parts|
          [ "table #{table}" ] +
            parts[:columns].map { |column| "column #{table}.#{column.first}" } +
            parts[:indexes].map { |index| "index #{table}.#{index.first}" } +
            parts[:foreign_keys].map { |key| "foreign key #{table}.#{key.first}" }
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require File.expand_path("../dummy/config/environment", __dir__)
  require_relative "test_schema"

  output, *versions = ARGV
  results = RailsErrorDashboard::MigrationRoundTrip::Runner.new(versions.map(&:to_i)).call
  File.write(output, JSON.generate(results))
end
