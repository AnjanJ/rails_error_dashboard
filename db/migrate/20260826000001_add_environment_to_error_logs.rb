# frozen_string_literal: true

# Records which environment an error came from (production, staging, uat, ...).
#
# RED had this column in v0.1.x and dropped it in the v1.0-launch refactor. It
# returns as a nullable string: NULL means "captured before this column
# existed", which is information the dashboard uses (no badge, matched as a
# wildcard by FindOrIncrementError and adopted on the next occurrence), not a
# gap to paper over with a default. `rails_error_dashboard:backfill_environments`
# fills NULLs from environment_info.rails_env for anyone who wants history too.
class AddEnvironmentToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    # Guard against the squashed schema migration having already added this
    # column -- without it, every later migration is silently cancelled.
    return if column_exists?(:rails_error_dashboard_error_logs, :environment)

    # 64 chars: long enough for "preprod-eu-west-2-canary", short enough that
    # the composite index below stays cheap on MySQL's utf8mb4 key limit.
    add_column :rails_error_dashboard_error_logs, :environment, :string, limit: 64

    # Mirrors index_error_logs_on_platform_and_occurred_at: the index filter is
    # "this environment, newest first".
    add_index :rails_error_dashboard_error_logs, [ :environment, :occurred_at ],
              name: "index_error_logs_on_environment_and_occurred_at"
  end
end
