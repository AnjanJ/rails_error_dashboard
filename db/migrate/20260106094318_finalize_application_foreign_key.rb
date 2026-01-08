class FinalizeApplicationForeignKey < ActiveRecord::Migration[7.0]
  def up
    # Make NOT NULL
    change_column_null :rails_error_dashboard_error_logs, :application_id, false

    # Add FK constraint
    add_foreign_key :rails_error_dashboard_error_logs,
                    :rails_error_dashboard_applications,
                    column: :application_id,
                    on_delete: :restrict
  end

  def down
    remove_foreign_key :rails_error_dashboard_error_logs, column: :application_id
    change_column_null :rails_error_dashboard_error_logs, :application_id, true
  end
end
