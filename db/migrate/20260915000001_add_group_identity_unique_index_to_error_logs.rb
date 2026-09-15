# frozen_string_literal: true

# Give an error group a database-enforced identity.
#
# FindOrIncrementError locks the row it finds, which makes concurrent
# *increments* safe. Creation had no such protection: two connections that both
# miss the unresolved lookup for one fingerprint both INSERT, and the
# RecordNotUnique retry branch below that miss was unreachable because no
# unique constraint existed to violate. Two rows, each occurrence_count 1,
# splitting counts, workflow and notifications at the exact moment a new fault
# fans out across a fleet.
#
# The identity is (application_id, error_hash, environment, group_window)
# restricted to unresolved rows:
#
#   * environment is a MATCH dimension — the same error in staging and in
#     production is legitimately two rows, so it belongs in the key.
#   * group_window is why this is not a blanket unique index. RED deliberately
#     opens a NEW unresolved group once the previous one's occurred_at falls
#     outside its 24 h window, so (application_id, error_hash, environment)
#     alone forbids intended behaviour. group_window is an immutable bucket
#     stamped at creation, so two racing creates (milliseconds apart) share a
#     bucket and collide, while a create after the window rolls over gets a
#     different bucket and is allowed.
#   * both are wrapped in COALESCE. In SQL NULL != NULL, so a plain index over
#     nullable columns would NOT constrain legacy rows: every NULL-environment
#     row (pre-0.11.0) and every NULL-group_window row (pre-this-migration) is
#     distinct from every other, and the duplicates this index exists to
#     prevent slip straight through the hole.
#   * WHERE resolved = false keeps reopen semantics intact. A resolved row and
#     its unresolved successor coexist, and several resolved rows for one
#     fingerprint are ordinary history.
#
# The index is a BACKSTOP, not the grouping mechanism. The 24 h lookup still
# runs first and catches the ordinary near-boundary case; the index only bites
# when two creates genuinely race, which is why a coarse bucket is sufficient.
#
# MySQL has no partial (filtered) indexes, so the index is skipped there and
# the pre-existing RecordNotUnique retry simply stays dormant, exactly as it is
# today. That is a real gap, documented rather than papered over. The column is
# still added on MySQL so the model behaves identically on every adapter.
class AddGroupIdentityUniqueIndexToErrorLogs < ActiveRecord::Migration[7.0]
  # CREATE INDEX CONCURRENTLY cannot run inside a transaction on PostgreSQL.
  disable_ddl_transaction!

  TABLE = :rails_error_dashboard_error_logs
  INDEX = "index_error_logs_on_group_identity"
  # Byte-identical to the expression in spec/dummy/db/schema.rb. SQLite echoes
  # an expression index back verbatim and bin/check-schema-parity compares the
  # echoed text, so these two spellings must not drift (note: no space after
  # the comma inside either COALESCE).
  EXPRESSION = "application_id, error_hash, COALESCE(environment,''), COALESCE(group_window,'')"

  def up
    return unless table_exists?(TABLE)

    unless column_exists?(TABLE, :group_window)
      # 10 chars: an ISO date bucket ("2026-09-15"). Short enough to keep the
      # composite index cheap under MySQL's utf8mb4 key limit.
      add_column TABLE, :group_window, :string, limit: 10
    end

    # Existing rows predate the column. Stamp each unresolved row from its own
    # occurred_at so the bucket means the same thing for history as it does for
    # new rows; anything that still collides after that is a genuine duplicate
    # and is merged below.
    backfill_group_window!

    return if mysql? # no partial indexes
    return if index_name_exists?(TABLE, INDEX)

    # A host upgrading may already hold duplicates created by the very race
    # this index prevents. Building the index over them would fail, so merge
    # them first: the survivor keeps the summed occurrence_count and the widest
    # time range, and the losers are deleted after their occurrence rows are
    # re-pointed at the survivor.
    deduplicate_existing_groups!

    if postgresql?
      add_index TABLE, EXPRESSION, name: INDEX, unique: true,
                where: "resolved = false", algorithm: :concurrently
    else
      add_index TABLE, EXPRESSION, name: INDEX, unique: true, where: "resolved = false"
    end
  end

  def down
    return unless table_exists?(TABLE)

    # Dropping the index and the column is reversible; merging the duplicate
    # groups it required is not — the losing rows and their original counts
    # are gone.
    raise ActiveRecord::IrreversibleMigration,
          "this migration merges duplicate error groups before creating #{INDEX}; the pre-merge rows cannot be restored"
  end

  private

  # Only unresolved rows need a bucket: the index covers `resolved = false`
  # only, and leaving resolved history NULL keeps the backfill cheap on a big
  # table.
  def backfill_group_window!
    quoted = connection.quote_column_name("group_window")
    connection.update(<<~SQL)
      UPDATE #{connection.quote_table_name(TABLE.to_s)}
      SET #{quoted} = #{window_expression}
      WHERE #{quoted} IS NULL
        AND resolved = #{quoted_false}
    SQL
  end

  # The same value ErrorLog#set_group_window computes in Ruby: occurred_at as
  # a UTC ISO date.
  def window_expression
    if postgresql?
      "to_char(occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD')"
    elsif mysql?
      "DATE_FORMAT(CONVERT_TZ(occurred_at, '+00:00', '+00:00'), '%Y-%m-%d')"
    else
      "strftime('%Y-%m-%d', occurred_at)"
    end
  end

  def deduplicate_existing_groups!
    duplicate_keys.each do |application_id, error_hash, env_key, window_key|
      # '' is the COALESCE stand-in for NULL (see duplicate_keys).
      environment = env_key.presence
      group_window = window_key.presence

      scope = ErrorLogRow.where(application_id: application_id, error_hash: error_hash, resolved: false)
      scope = environment.nil? ? scope.where(environment: nil) : scope.where(environment: environment)
      scope = group_window.nil? ? scope.where(group_window: nil) : scope.where(group_window: group_window)

      rows = scope.order(:id).to_a
      next if rows.size < 2

      survivor = rows.first
      losers = rows[1..]

      total = rows.sum { |r| r.occurrence_count.to_i }
      first_seen = rows.filter_map { |r| r.occurred_at }.min
      last_seen = rows.filter_map { |r| r.last_seen_at || r.occurred_at }.max

      if occurrences_table?
        OccurrenceRow.where(error_log_id: losers.map(&:id)).update_all(error_log_id: survivor.id)
      end

      updates = { occurrence_count: total }
      updates[:occurred_at] = first_seen if first_seen
      updates[:last_seen_at] = last_seen if last_seen
      ErrorLogRow.where(id: survivor.id).update_all(updates)
      ErrorLogRow.where(id: losers.map(&:id)).delete_all

      say "merged #{losers.size} duplicate group(s) into error log #{survivor.id}", true
    end
  end

  # The identity tuples that currently have more than one unresolved row.
  # COALESCE mirrors the index expression, so a set of NULL-environment rows
  # counts as one group rather than as N distinct ones.
  def duplicate_keys
    # PostgreSQL requires every selected column to appear in GROUP BY or an
    # aggregate, so the COALESCE expressions are selected rather than the bare
    # columns (SQLite tolerates the bare form; PG raises GroupingError).
    # '' therefore means NULL here, which deduplicate_existing_groups! maps
    # back when it scopes each group.
    connection.select_rows(<<~SQL)
      SELECT application_id,
             error_hash,
             COALESCE(environment, '') AS env_key,
             COALESCE(group_window, '') AS window_key
      FROM #{connection.quote_table_name(TABLE.to_s)}
      WHERE resolved = #{quoted_false}
      GROUP BY application_id, error_hash, COALESCE(environment, ''), COALESCE(group_window, '')
      HAVING COUNT(*) > 1
    SQL
  end

  def quoted_false
    postgresql? ? "false" : "0"
  end

  def occurrences_table?
    table_exists?(:rails_error_dashboard_error_occurrences)
  end

  def postgresql?
    connection.adapter_name.downcase == "postgresql"
  end

  def mysql?
    connection.adapter_name.downcase.match?(/mysql|trilogy/)
  end

  # Bare AR classes: the gem's real models carry callbacks, default scopes and
  # a possibly separate connection. A migration must see the table it is
  # migrating, exactly as it is on disk right now.
  class ErrorLogRow < ActiveRecord::Base
    self.table_name = "rails_error_dashboard_error_logs"
    self.inheritance_column = nil
  end

  class OccurrenceRow < ActiveRecord::Base
    self.table_name = "rails_error_dashboard_error_occurrences"
    self.inheritance_column = nil
  end
end
