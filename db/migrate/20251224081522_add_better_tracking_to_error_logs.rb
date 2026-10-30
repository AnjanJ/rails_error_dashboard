# up/down rather than `change`: the column_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddBetterTrackingToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    # Skip if squashed migration already added these columns
    return if column_exists?(:rails_error_dashboard_error_logs, :error_hash)

    add_column :rails_error_dashboard_error_logs, :error_hash, :string
    add_column :rails_error_dashboard_error_logs, :first_seen_at, :datetime
    add_column :rails_error_dashboard_error_logs, :last_seen_at, :datetime
    add_column :rails_error_dashboard_error_logs, :occurrence_count, :integer, default: 1, null: false

    add_index :rails_error_dashboard_error_logs, :error_hash
    add_index :rails_error_dashboard_error_logs, :first_seen_at
    add_index :rails_error_dashboard_error_logs, :last_seen_at
    add_index :rails_error_dashboard_error_logs, :occurrence_count
  end

  def down
    return unless table_exists?(:rails_error_dashboard_error_logs)

    # PostgreSQL would drop this index with the column and say nothing, and no up
    # puts it back. It's what stops duplicate error groups.
    if index_name_exists?(:rails_error_dashboard_error_logs, "index_error_logs_on_group_identity")
      raise ActiveRecord::MigrationError, "index_error_logs_on_group_identity needs error_hash, and nothing would put it back"
    end

    %i[error_hash first_seen_at last_seen_at occurrence_count].each do |column|
      remove_index :rails_error_dashboard_error_logs, column, if_exists: true
      remove_column :rails_error_dashboard_error_logs, column if column_exists?(:rails_error_dashboard_error_logs, column)
    end
  end
end
