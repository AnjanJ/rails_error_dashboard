# frozen_string_literal: true

# Dropping RED's tables inside a spec. SQLite and PostgreSQL run DDL in a
# transaction, so the drop happens inside a savepoint that is always rolled
# back and the shared test database keeps its tables. MySQL commits DDL
# implicitly, so these examples skip there.
module RedTableDropHelpers
  RED_TABLE = /\Arails_error_dashboard_/

  def red_connection
    RailsErrorDashboard::ErrorLogsRecord.connection
  end

  def red_tables(connection = red_connection)
    connection.tables.grep(RED_TABLE).sort
  end

  # One row behind every foreign key between RED's tables. SQLite only refuses
  # to drop a referenced table while rows still reference it, so with empty
  # tables a wrong drop order would pass.
  def seed_one_row_per_foreign_key
    application = create(:application)
    parent = create(:error_log, application: application)
    child = create(:error_log, application: application)
    create(:error_occurrence, error_log: parent)
    create(:cascade_pattern, parent_error: parent, child_error: child)
    RailsErrorDashboard::ErrorComment.create!(error_log: parent, author_name: "spec", body: "spec")
    RailsErrorDashboard::DiagnosticDump.create!(application: application, dump_data: "{}", captured_at: Time.current)
  end

  # Yields the error database connection inside a savepoint that is always
  # rolled back, then clears the schema cache so no model remembers a table
  # as dropped.
  def with_rolled_back_ddl
    unless red_connection.supports_ddl_transactions?
      skip "DDL is not transactional on #{red_connection.adapter_name}"
    end

    RailsErrorDashboard::ErrorLogsRecord.transaction(requires_new: true) do
      yield red_connection
      raise ActiveRecord::Rollback
    end
  ensure
    red_connection.schema_cache.clear!
    RailsErrorDashboard::ErrorLogsRecord.descendants.each(&:reset_column_information)
  end
end

RSpec.configure { |config| config.include RedTableDropHelpers }
