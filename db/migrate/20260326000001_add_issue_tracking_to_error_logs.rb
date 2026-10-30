# frozen_string_literal: true

# Add columns for linking errors to external issue trackers (GitHub, GitLab, Codeberg/Gitea/Forgejo).
# These columns store the relationship between an error and its tracked issue.
#
# See: https://github.com/AnjanJ/rails_error_dashboard
#
# up/down rather than `change`: the column_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddIssueTrackingToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:rails_error_dashboard_error_logs)

    add_column :rails_error_dashboard_error_logs, :external_issue_url, :string unless column_exists?(:rails_error_dashboard_error_logs, :external_issue_url)
    add_column :rails_error_dashboard_error_logs, :external_issue_number, :integer unless column_exists?(:rails_error_dashboard_error_logs, :external_issue_number)
    add_column :rails_error_dashboard_error_logs, :external_issue_provider, :string, limit: 20 unless column_exists?(:rails_error_dashboard_error_logs, :external_issue_provider)
  end

  def down
    return unless table_exists?(:rails_error_dashboard_error_logs)

    remove_column :rails_error_dashboard_error_logs, :external_issue_url, if_exists: true
    remove_column :rails_error_dashboard_error_logs, :external_issue_number, if_exists: true
    remove_column :rails_error_dashboard_error_logs, :external_issue_provider, if_exists: true
  end
end
