# frozen_string_literal: true

# up/down rather than `change`: the column_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddEnvironmentInfoToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    unless column_exists?(:rails_error_dashboard_error_logs, :environment_info)
      add_column :rails_error_dashboard_error_logs, :environment_info, :text
    end
  end

  def down
    return unless table_exists?(:rails_error_dashboard_error_logs)

    remove_column :rails_error_dashboard_error_logs, :environment_info if column_exists?(:rails_error_dashboard_error_logs, :environment_info)
  end
end
