# frozen_string_literal: true

class CreateErrorComments < ActiveRecord::Migration[8.0]
  def change
    # Skip if squashed migration already ran
    return if connection.table_exists?(:rails_error_dashboard_schema_markers)

    create_table :rails_error_dashboard_error_comments do |t|
      t.references :error_log,
                   null: false,
                   foreign_key: { to_table: :rails_error_dashboard_error_logs }
      t.string :author_name, null: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :rails_error_dashboard_error_comments, [ :error_log_id, :created_at ],
              name: 'index_error_comments_on_error_and_time'
  end
end
