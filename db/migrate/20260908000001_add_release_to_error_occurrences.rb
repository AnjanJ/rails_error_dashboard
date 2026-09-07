# frozen_string_literal: true

# Release attribution belongs on the occurrence, not the group.
#
# An ErrorLog row is a GROUP: it keeps the app_version/git_sha of the first
# capture in its window and recurrences do not touch them. So an error first
# seen in v1 that kept firing after the v2 deploy was reported entirely under
# v1, and the release timeline could not answer "did this deploy make things
# worse". Each ErrorOccurrence now records the release it happened under, and
# ReleaseTimeline counts occurrences per release.
#
# Existing occurrences are backfilled from their group's release. That is the
# same attribution the dashboard showed before this migration (no worse), and
# it keeps historical releases populated instead of dropping to zero.
class AddReleaseToErrorOccurrences < ActiveRecord::Migration[7.0]
  def up
    return if column_exists?(:rails_error_dashboard_error_occurrences, :app_version)

    add_column :rails_error_dashboard_error_occurrences, :app_version, :string
    add_column :rails_error_dashboard_error_occurrences, :git_sha, :string
    add_index :rails_error_dashboard_error_occurrences, [ :app_version, :occurred_at ],
              name: "index_error_occurrences_on_version_and_time"

    # Correlated subqueries rather than UPDATE ... FROM / JOIN: the one form
    # SQLite, PostgreSQL and MySQL all accept.
    execute <<~SQL.squish
      UPDATE rails_error_dashboard_error_occurrences
      SET app_version = (
            SELECT app_version FROM rails_error_dashboard_error_logs
            WHERE rails_error_dashboard_error_logs.id = rails_error_dashboard_error_occurrences.error_log_id
          ),
          git_sha = (
            SELECT git_sha FROM rails_error_dashboard_error_logs
            WHERE rails_error_dashboard_error_logs.id = rails_error_dashboard_error_occurrences.error_log_id
          )
      WHERE app_version IS NULL
    SQL
  end

  def down
    remove_index :rails_error_dashboard_error_occurrences, name: "index_error_occurrences_on_version_and_time"
    remove_column :rails_error_dashboard_error_occurrences, :git_sha
    remove_column :rails_error_dashboard_error_occurrences, :app_version
  end
end
