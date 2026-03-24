# frozen_string_literal: true

class AddMutedToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    return if column_exists?(:rails_error_dashboard_error_logs, :muted)

    add_column :rails_error_dashboard_error_logs, :muted, :boolean, default: false, null: false
    add_column :rails_error_dashboard_error_logs, :muted_at, :datetime
    add_column :rails_error_dashboard_error_logs, :muted_by, :string
    add_column :rails_error_dashboard_error_logs, :muted_reason, :string

    add_index :rails_error_dashboard_error_logs, :muted
  end
end
