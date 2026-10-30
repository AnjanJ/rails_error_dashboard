# frozen_string_literal: true

# up/down rather than `change`: the column_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddMutedToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    return if column_exists?(:rails_error_dashboard_error_logs, :muted)

    add_column :rails_error_dashboard_error_logs, :muted, :boolean, default: false, null: false
    add_column :rails_error_dashboard_error_logs, :muted_at, :datetime
    add_column :rails_error_dashboard_error_logs, :muted_by, :string
    add_column :rails_error_dashboard_error_logs, :muted_reason, :string

    add_index :rails_error_dashboard_error_logs, :muted
  end

  def down
    return unless table_exists?(:rails_error_dashboard_error_logs)

    %i[muted muted_at muted_by muted_reason].each do |column|
      remove_index :rails_error_dashboard_error_logs, column, if_exists: true
      remove_column :rails_error_dashboard_error_logs, column if column_exists?(:rails_error_dashboard_error_logs, column)
    end
  end
end
