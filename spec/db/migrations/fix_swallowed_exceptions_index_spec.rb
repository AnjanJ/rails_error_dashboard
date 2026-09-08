# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("../../db/migrate/20260325000001_fix_swallowed_exceptions_index_for_mysql").to_s

# This migration ships in the gem and the installer copies it into the host
# app, so a failure here aborts `rails db:migrate` for a real user and leaves
# every later migration unapplied.
#
# It has to be executed, not just asserted against the migrated schema: the bug
# it regresses was in the migration's own body, where index_exists? was called
# without the column argument it requires. That raises ArgumentError on Rails 8
# and is invisible to any spec that only inspects the resulting schema.
RSpec.describe FixSwallowedExceptionsIndexForMysql, type: :migration do
  # DDL and transactions do not mix on MySQL (implicit commit); spec/support/
  # database_cleaner.rb runs :migration examples outside a transaction.
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.connection }
  let(:table) { :rails_error_dashboard_swallowed_exceptions }
  let(:index_name) { "index_swallowed_exceptions_upsert_key" }
  let(:upsert_columns) do
    %w[exception_class raise_location rescue_location period_hour application_id]
  end

  # Rebuild the table standalone so the suite's real schema is left alone.
  def build_table(index_columns: nil)
    connection.create_table(table, force: true) do |t|
      t.string   :exception_class, null: false, limit: 250
      t.string   :raise_location,  null: false, limit: 250
      t.string   :rescue_location, limit: 250
      t.datetime :period_hour,     null: false
      t.integer  :raise_count,     null: false, default: 0
      t.integer  :rescue_count,    null: false, default: 0
      t.datetime :last_seen_at
      t.bigint   :application_id
      t.timestamps
    end

    return if index_columns.nil?

    connection.add_index(table, index_columns, unique: true, name: index_name)
  end

  def upsert_index
    connection.indexes(table).find { |i| i.name == index_name }
  end

  # Restore the table exactly as db/schema.rb defines it (which matches the
  # migrated shape: 250-char strings, bigint application_id) with all four
  # indexes, so the schema is right for any spec that runs after this file.
  def restore_schema_table
    connection.drop_table(table, if_exists: true)
    connection.create_table(table, force: :cascade) do |t|
      t.string   :exception_class, null: false, limit: 250
      t.string   :raise_location,  null: false, limit: 250
      t.string   :rescue_location, limit: 250
      t.datetime :period_hour,     null: false
      t.integer  :raise_count,     null: false, default: 0
      t.integer  :rescue_count,    null: false, default: 0
      t.datetime :last_seen_at
      t.bigint   :application_id
      t.timestamps
    end
    connection.add_index table, %w[application_id period_hour],
      name: "index_swallowed_exceptions_on_app_and_hour"
    connection.add_index table, %w[exception_class period_hour],
      name: "index_swallowed_exceptions_on_class_and_hour"
    connection.add_index table, upsert_columns, unique: true, name: index_name
    connection.add_index table, %w[period_hour],
      name: "index_swallowed_exceptions_on_period_hour"
  end

  # These examples drop and rebuild the table, so it is restored to the shape
  # the rest of the suite expects rather than left in whichever state the last
  # example produced.
  around do |example|
    was_verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = was_verbose
    restore_schema_table
  end

  describe "#up" do
    it "runs when the oversized index is present" do
      build_table(index_columns: upsert_columns)

      expect { described_class.new.up }.not_to raise_error

      expect(upsert_index).to be_present
      expect(upsert_index.columns).to eq(upsert_columns)
      expect(upsert_index.unique).to be(true)
    end

    # The MySQL case the migration exists for: the original migration failed
    # partway, so the index was never created.
    it "runs when the index is absent" do
      build_table(index_columns: nil)

      expect { described_class.new.up }.not_to raise_error

      expect(upsert_index).to be_present
      expect(upsert_index.columns).to eq(upsert_columns)
    end

    # The index name is taken but by an index over different columns. Checking
    # by columns would report "absent" here, skip the remove, and then fail on
    # a duplicate index name when re-adding it.
    it "reclaims the index name when it is held by different columns" do
      build_table(index_columns: %w[exception_class period_hour])

      expect { described_class.new.up }.not_to raise_error

      expect(upsert_index.columns).to eq(upsert_columns)
    end

    it "shrinks the string columns to fit MySQL's index key limit" do
      build_table(index_columns: upsert_columns)

      described_class.new.up

      limits = connection.columns(table).each_with_object({}) do |column, acc|
        acc[column.name] = column.limit
      end

      expect(limits["exception_class"]).to eq(250)
      expect(limits["raise_location"]).to eq(250)
      expect(limits["rescue_location"]).to eq(250)
    end
  end

  describe "#down" do
    mysql = ActiveRecord::Base.connection.adapter_name.match?(/mysql|trilogy/i)

    it "reverses without raising and restores the index", unless: mysql do
      build_table(index_columns: upsert_columns)
      migration = described_class.new
      migration.up

      expect { migration.down }.not_to raise_error

      expect(upsert_index).to be_present
      expect(upsert_index.columns).to eq(upsert_columns)
    end

    it "is explicitly irreversible on MySQL, whose key limit the old index exceeds", if: mysql do
      build_table(index_columns: upsert_columns)
      migration = described_class.new
      migration.up

      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration, /3072/)
      expect(upsert_index).to be_present # nothing half-applied
    end
  end

  describe "guard clause" do
    it "is a no-op when the table does not exist" do
      connection.drop_table(table, if_exists: true)

      expect { described_class.new.up }.not_to raise_error
      expect(connection.table_exists?(table)).to be(false)
    end
  end
end
