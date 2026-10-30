class FinalizeApplicationForeignKey < ActiveRecord::Migration[7.0]
  def up
    # Skip if squashed migration already added the foreign key
    return if foreign_key_exists?(:rails_error_dashboard_error_logs,
                                   :rails_error_dashboard_applications,
                                   column: :application_id)

    # Make NOT NULL
    change_column_null :rails_error_dashboard_error_logs, :application_id, false

    # Add FK constraint
    add_foreign_key :rails_error_dashboard_error_logs,
                    :rails_error_dashboard_applications,
                    column: :application_id,
                    on_delete: :restrict
  end

  def down
    # The table is named because SQLite before Rails 8.1 guesses it from the
    # column, as "applications", and raises when no foreign key matches.
    remove_foreign_key :rails_error_dashboard_error_logs, :rails_error_dashboard_applications, column: :application_id
    change_column_null :rails_error_dashboard_error_logs, :application_id, true
  end
end
