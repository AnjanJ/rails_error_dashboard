# frozen_string_literal: true

# When a notification was last sent for this error group.
#
# The notification cooldown used to live in a Hash inside each process. Every
# Puma worker and every job process had its own copy, so one bad deploy that
# reopened an error notified once PER PROCESS, and a restart forgot the
# cooldown entirely.
#
# With the timestamp on the row the cooldown is claimed in the database with a
# single conditional UPDATE, which exactly one process can win:
#
#   UPDATE ... SET last_notified_at = now
#   WHERE id = ? AND (last_notified_at IS NULL OR last_notified_at < cutoff)
#
# No index: the row is always addressed by primary key.
#
# Nullable, no default: NULL means "never notified". Until this migration has
# run the gem falls back to the in-process cooldown, so upgrading the gem
# before migrating is safe.
#
# up/down rather than `change`: the column_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddLastNotifiedAtToErrorLogs < ActiveRecord::Migration[7.0]
  TABLE = :rails_error_dashboard_error_logs

  def up
    return unless table_exists?(TABLE)
    return if column_exists?(TABLE, :last_notified_at)

    add_column TABLE, :last_notified_at, :datetime
  end

  def down
    return unless table_exists?(TABLE)
    return unless column_exists?(TABLE, :last_notified_at)

    remove_column TABLE, :last_notified_at
  end
end
