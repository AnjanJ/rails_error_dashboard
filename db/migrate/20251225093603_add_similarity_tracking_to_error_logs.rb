class AddSimilarityTrackingToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    # Skip if squashed migration already added these columns
    return if column_exists?(:rails_error_dashboard_error_logs, :similarity_score)

    add_column :rails_error_dashboard_error_logs, :similarity_score, :float
    add_column :rails_error_dashboard_error_logs, :backtrace_signature, :string

    add_index :rails_error_dashboard_error_logs, :similarity_score
    add_index :rails_error_dashboard_error_logs, :backtrace_signature
  end
end
