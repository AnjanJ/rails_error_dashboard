# up/down rather than `change`: the column_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddSimilarityTrackingToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    # Skip if squashed migration already added these columns
    return if column_exists?(:rails_error_dashboard_error_logs, :similarity_score)

    add_column :rails_error_dashboard_error_logs, :similarity_score, :float
    add_column :rails_error_dashboard_error_logs, :backtrace_signature, :string

    add_index :rails_error_dashboard_error_logs, :similarity_score
    add_index :rails_error_dashboard_error_logs, :backtrace_signature
  end

  def down
    return unless table_exists?(:rails_error_dashboard_error_logs)

    %i[similarity_score backtrace_signature].each do |column|
      remove_index :rails_error_dashboard_error_logs, column, if_exists: true
      remove_column :rails_error_dashboard_error_logs, column, if_exists: true
    end
  end
end
