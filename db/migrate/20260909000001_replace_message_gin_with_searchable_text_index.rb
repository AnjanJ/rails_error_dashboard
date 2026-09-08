# frozen_string_literal: true

# The dashboard's PostgreSQL full-text search (Queries::ErrorsList#filter_by_search)
# matches against message, backtrace and error_type together:
#
#   to_tsvector('english', COALESCE(message, '') || ' ' || COALESCE(backtrace, '') || ' ' || COALESCE(error_type, ''))
#
# PostgreSQL uses an expression index only when the query's expression is
# identical to the index's, so of the two GIN indexes defined over time only
# one can serve that search:
#
#   index_error_logs_on_message_gin       to_tsvector('english', message)              never used by any query
#   index_error_logs_on_searchable_text   the expression above                          the one the search needs
#
# Which of them a host has depends on how it was installed. Hosts that ran the
# incremental chain got both; hosts installed from the squashed first migration
# got neither (the later index migrations skip themselves once the squash's
# composite indexes exist), and 0.11.7 then added only the message-only one.
#
# This converges every install on index_error_logs_on_searchable_text alone.
# No-op on other adapters.
class ReplaceMessageGinWithSearchableTextIndex < ActiveRecord::Migration[7.0]
  TABLE = :rails_error_dashboard_error_logs

  def up
    return unless postgresql?
    return unless table_exists?(TABLE)

    execute <<~SQL
      CREATE INDEX IF NOT EXISTS index_error_logs_on_searchable_text
      ON rails_error_dashboard_error_logs
      USING gin(to_tsvector('english',
        COALESCE(message, '') || ' ' || COALESCE(backtrace, '') || ' ' || COALESCE(error_type, '')
      ))
    SQL

    execute "DROP INDEX IF EXISTS index_error_logs_on_message_gin"
  end

  def down
    return unless postgresql?

    # There is no single state to return to: before this migration a host had
    # either both indexes or only the message-only one, depending on its
    # install path. Dropping searchable_text here would take away, on
    # incremental-chain hosts, an index they had before, and nothing needs
    # message_gin back. Earlier gem versions run unchanged against the
    # converged schema.
    raise ActiveRecord::IrreversibleMigration,
          "this migration converges two index layouts (see its header); the previous layout is not recoverable"
  end

  private

  def postgresql?
    connection.adapter_name.downcase == "postgresql"
  end
end
