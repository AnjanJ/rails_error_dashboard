# frozen_string_literal: true

class CreateCascadePatterns < ActiveRecord::Migration[7.0]
  def change
    # Skip if squashed migration already created this table
    return if table_exists?(:rails_error_dashboard_cascade_patterns)

    create_table :rails_error_dashboard_cascade_patterns do |t|
      t.references :parent_error, null: false, foreign_key: { to_table: :rails_error_dashboard_error_logs }
      t.references :child_error, null: false, foreign_key: { to_table: :rails_error_dashboard_error_logs }
      t.integer :frequency, default: 1, null: false
      t.float :avg_delay_seconds
      t.float :cascade_probability # 0.0-1.0, percentage of time parent leads to child
      t.datetime :last_detected_at

      t.timestamps
    end

    # Composite index for finding cascade patterns
    add_index :rails_error_dashboard_cascade_patterns, [ :parent_error_id, :child_error_id ],
              name: 'index_cascade_patterns_on_parent_and_child',
              unique: true

    # Index for finding children of a parent error
    add_index :rails_error_dashboard_cascade_patterns, :parent_error_id,
              name: 'index_cascade_patterns_on_parent'

    # Index for finding parents of a child error
    add_index :rails_error_dashboard_cascade_patterns, :child_error_id,
              name: 'index_cascade_patterns_on_child'

    # Index for finding by probability (for high-confidence cascades)
    add_index :rails_error_dashboard_cascade_patterns, :cascade_probability,
              name: 'index_cascade_patterns_on_probability'
  end
end
