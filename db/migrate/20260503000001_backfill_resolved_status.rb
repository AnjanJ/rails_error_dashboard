# frozen_string_literal: true

# Backfill `status` column for errors that were bulk-resolved before v0.6.3.
#
# Versions 0.6.0 through 0.6.2 had a bug in BatchResolveErrors that set
# `resolved: true` and `resolved_at` but skipped the `status` column. The
# errors-index "Resolved" filter pill queries `where(status: 'resolved')`,
# so bulk-resolved errors silently disappeared from that view even though
# they were marked resolved.
#
# This migration is idempotent: it only updates rows that are out-of-sync
# (resolved but not status='resolved'). Running it twice is a no-op.
#
# See: https://github.com/AnjanJ/rails_error_dashboard
class BackfillResolvedStatus < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:rails_error_dashboard_error_logs)
    return unless column_exists?(:rails_error_dashboard_error_logs, :status)
    return unless column_exists?(:rails_error_dashboard_error_logs, :resolved)

    # Use ActiveRecord update_all so the count is portable across adapters
    # (PostgreSQL, MySQL, SQLite all return the affected row count).
    table = ActiveRecord::Base.connection.quote_table_name("rails_error_dashboard_error_logs")
    klass = Class.new(ActiveRecord::Base) { self.table_name = "rails_error_dashboard_error_logs" }
    updated = klass.where(resolved: true).where("status IS NULL OR status != ?", "resolved")
                   .update_all(status: "resolved")

    say "Backfilled status='resolved' on #{updated} error log(s) that were bulk-resolved on v0.6.0–v0.6.2."
  end

  def down
    # No-op: we cannot reliably distinguish errors that were bulk-resolved
    # before the fix from errors that are legitimately resolved now. Leaving
    # status='resolved' is the safe choice on rollback.
  end
end
