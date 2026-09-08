# frozen_string_literal: true

# Fresh PostgreSQL installs never got two indexes the query layer was written
# for: 20251225071314_add_optimized_indexes_to_error_logs returns early once
# its composite indexes exist, and the squashed first migration creates those
# composites but not the PostgreSQL-only partial index on unresolved rows or
# the GIN index behind full-text message search. Existing installs that ran
# the incremental chain have them; this adds them wherever they are missing.
# No-op on other adapters.
class AddMissingPostgresqlIndexesToErrorLogs < ActiveRecord::Migration[7.0]
  TABLE = :rails_error_dashboard_error_logs

  def up
    return unless postgresql?
    return unless table_exists?(TABLE)

    unless index_name_exists?(TABLE, "index_error_logs_on_occurred_at_unresolved")
      add_index TABLE, :occurred_at, where: "resolved = false",
                name: "index_error_logs_on_occurred_at_unresolved"
    end

    execute <<-SQL
      CREATE INDEX IF NOT EXISTS index_error_logs_on_message_gin
      ON rails_error_dashboard_error_logs
      USING gin(to_tsvector('english', message))
    SQL
  end

  def down
    return unless postgresql?
    return unless table_exists?(TABLE)

    remove_index TABLE, name: "index_error_logs_on_occurred_at_unresolved", if_exists: true
    execute "DROP INDEX IF EXISTS index_error_logs_on_message_gin"
  end

  private

  def postgresql?
    connection.adapter_name.downcase == "postgresql"
  end
end
